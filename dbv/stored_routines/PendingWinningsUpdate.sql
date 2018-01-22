DROP procedure IF EXISTS `PendingWinningsUpdate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PendingWinningsUpdate`(gamePlayId BIGINT, userID BIGINT, newStatus INT(11), newPayoutTypeId INT(11), userComments VARCHAR(250), OUT statusCode INT)
root:BEGIN
	-- Added code to update coupon status
-- Committing to DBV
	/*
	-- Statuses
	 -- 0 Success
	 -- 1 Status cannot be changed, it is already paid
	 -- 2 Invalid Payout Type Id
	-- 3 Coupon is blocked, cannot change pending winnings 	
	*/ 
	DECLARE oldStatus, oldPayoutTypeId, participationPrizeNo INT(11);
	DECLARE dateUpdated DATETIME;
	DECLARE clientStatID, couponID, participationID, paymentMethodID, newBalanceAccountID, balanceManualTransactionID, gameRoundID BIGINT;
	DECLARE pendingAmount, exchangeRate, grossToAdd, netToAdd DECIMAL(18,5);
	DECLARE notificationEnabled TINYINT DEFAULT 0;
  DECLARE ruleEngineEnabled TINYINT(1) DEFAULT 0;
	DECLARE openParticipations, newCouponStatus, winParticipations, paidParticipations, licenseTypeID INT(4) DEFAULT 0;
	DECLARE currentCouponStatus INT(4);
	DECLARE platformTypeID int(11) DEFAULT 1;

	SET dateUpdated = NOW();
	SET statusCode = 0;

	SELECT pending_winning_status_id, payout_type_id, participation_prize_no 
    INTO oldStatus, oldPayoutTypeId, participationPrizeNo 
    FROM gaming_pending_winnings WHERE game_play_id = gamePlayId;

  SELECT gs1.value_bool as vb1
  INTO ruleEngineEnabled
  FROM gaming_settings gs1 
  WHERE gs1.name='RULE_ENGINE_ENABLED';	

	IF (oldStatus=2) THEN
		SET statusCode=1;
		LEAVE root;
	END IF;

	IF (statusCode=0) THEN
		SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

		IF (newPayoutTypeId IS NULL AND newStatus=2) THEN
			SET statusCode=2;
			LEAVE root;
		END IF;

		SELECT client_stat_id, base_amount, lottery_coupon_id,lottery_participation_id INTO clientStatID, pendingAmount, couponID, participationID
		FROM gaming_pending_winnings
		WHERE game_play_id=gamePlayId;
		
		/*  Addition to get the platformTypeID  BO(platformTypeID)*/
		-- 
		SELECT  gaming_game_plays.platform_type_id
		INTO  platformTypeID
		FROM gaming_game_plays_lottery_entries  FORCE INDEX (lottery_participation_id)
		STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (PRIMARY) ON gaming_lottery_participations.lottery_participation_id = gaming_game_plays_lottery_entries.lottery_participation_id 
		STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery_entries.game_play_id
		STRAIGHT_JOIN gaming_game_plays_lottery FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
		STRAIGHT_JOIN gaming_lottery_draws ON gaming_lottery_draws.lottery_draw_id = gaming_game_plays_lottery_entries.lottery_draw_id
		STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id = gaming_lottery_draws.game_id
		STRAIGHT_JOIN gaming_operators ON gaming_operators.operator_id = gaming_operator_games.operator_id AND gaming_operators.is_main_operator = 1
		STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (PRIMARY) ON gaming_game_rounds.game_round_id = gaming_game_plays.game_round_id
		WHERE gaming_game_plays_lottery_entries.lottery_participation_id = participationID;

		-- Get the Player channel
		CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, @platformTypeID, @platformType, @channelTypeID, @channelType);
		/* EO(platformTypeID)*/
		

		/* get game round ID */
		SELECT game_round_id INTO gameRoundID
		FROM gaming_game_rounds FORCE INDEX (sb_extra_id)
		WHERE gaming_game_rounds.sb_extra_id = participationID AND license_type_id IN (6, 7);

		SELECT lottery_coupon_status_id, license_type_id INTO currentCouponStatus, licenseTypeID FROM gaming_lottery_coupons WHERE lottery_coupon_id=couponID;

	    IF(currentCouponStatus = 2109 OR currentCouponStatus = 2110) THEN
			SET statusCode=3;
			LEAVE root;			
		END IF;

		IF (newStatus=3) THEN -- Declined
			UPDATE gaming_client_stats AS gcs
			SET pending_winning_real= pending_winning_real-pendingAmount
			WHERE client_stat_id=clientStatID;
			
			UPDATE gaming_game_plays 
			SET pending_winning_real=(pending_winning_real-pendingAmount)
			WHERE game_play_id=gamePlayId;

		ELSEIF (newStatus=2) THEN -- Approved and paid
			SELECT exchange_rate INTO exchangeRate 
			FROM gaming_client_stats gcs
			JOIN gaming_operator_currency goc ON gcs.currency_id=goc.currency_id 
			WHERE gcs.client_stat_id=clientStatID
			LIMIT 1;
            
			SELECT SUM(gross) AS gross, SUM(net) AS net
			INTO grossToAdd, netToAdd
			FROM gaming_lottery_participation_prizes FORCE INDEX (lottery_participation_id)
			WHERE lottery_participation_id = participationID
			GROUP BY lottery_participation_id;

			UPDATE gaming_lottery_coupons
			SET 
				win_gross_amount=IFNULL(win_gross_amount,0)+grossToAdd, win_net_amount=IFNULL(win_net_amount,0)+netToAdd,
				win_tax_amount=IFNULL(win_tax_amount,0)+(grossToAdd-netToAdd), win_amount=IFNULL(win_amount,0) + grossToAdd
			WHERE gaming_lottery_coupons.lottery_coupon_id=couponID;


			INSERT INTO gaming_game_plays 
				(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, bonus_lost, bonus_win_locked_lost, jackpot_contribution, TIMESTAMP, game_id, game_manufacturer_id,operator_game_id, client_id, client_stat_id, 
				session_id, game_round_id, payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, game_play_message_type_id, license_type_id, pending_bet_real,
				pending_bet_bonus, bet_from_real, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, sb_bet_id, sb_extra_id, pending_winning_real, sign_mult)
			SELECT
				pendingAmount,
				pendingAmount / exchangeRate,
				exchangeRate,
				pendingAmount,
				0,
				0,
				0,
				0,
				0,
				NOW(),
				gldt.game_id,
				gldt.game_manufacturer_id,
				gog.operator_game_id,
				gaming_client_stats.client_id,
				clientStatID,
				0,
				gameRoundID,
				gaming_payment_transaction_type.payment_transaction_type_id,
				1,
				(current_real_balance + pendingAmount),
				ROUND(current_bonus_balance + current_bonus_win_locked_balance, 0),
				current_bonus_win_locked_balance,
				gaming_client_stats.currency_id,
				0,
				game_play_message_type_id,
				licenseTypeID,
				pending_bets_real,
				pending_bets_bonus,
				gaming_client_stats.bet_from_real,
				NULL,
				0,
				gaming_client_stats.current_loyalty_points,
				0,
				(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`),
				couponID,
				participationID,
				pendingAmount * (-1),
				1
			FROM gaming_payment_transaction_type
			JOIN gaming_client_stats ON gaming_payment_transaction_type.name = 'Win' AND gaming_client_stats.client_stat_id = clientStatID
			JOIN gaming_game_play_message_types ON gaming_game_play_message_types.`name` = 
			CAST(CASE licenseTypeID 
				WHEN 6 THEN 'LotteryWin'
				WHEN 7 THEN 'SportsPoolWin' END AS CHAR(80))
			JOIN gaming_lottery_participations glp ON glp.lottery_participation_id = participationID
			JOIN gaming_lottery_dbg_tickets gldt ON glp.lottery_dbg_ticket_id = gldt.lottery_dbg_ticket_id
			JOIN gaming_operator_games gog ON gldt.game_id = gog.game_id;

			SET @newGamePlayID=LAST_INSERT_ID();
	  
      
      IF (ruleEngineEnabled) THEN
          IF NOT EXISTS (SELECT event_table_id FROM gaming_event_rows WHERE event_table_id=1 AND elem_id=@newGamePlayID) THEN
    		    INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, @newGamePlayID
              ON DUPLICATE KEY UPDATE elem_id=VALUES(elem_id);
          END IF;
      END IF;
      
      
    
    
			/* show wins per participation (mostly for reports) */
			INSERT INTO 
				gaming_game_plays_lottery_entries (game_play_id, lottery_draw_id, lottery_participation_id, amount_total, amount_real, amount_bonus, amount_bonus_win_locked, amount_ring_fenced, amount_free_bet, loyalty_points, loyalty_points_bonus, lottery_participation_prize_id)
			SELECT
				game_play_id,
				glp.lottery_draw_id,
				glpp.lottery_participation_id,
				pendingAmount,
				pendingAmount,
				0 /*amount_bonus*/ ,
				0 /*amount_bonus_win_locked*/ ,
				0 /*amount_ring_fenced*/ ,
				0 /*amount_free_bet*/ ,
				0 /*loyalty_points*/ ,
				0 /*loyalty_points_bonus*/ ,
				glpp.lottery_participation_prize_id
			FROM gaming_game_plays
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'Win'
			JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = clientStatID
			JOIN gaming_lottery_participations glp ON glp.lottery_participation_id = participationID
			JOIN gaming_lottery_participation_prizes glpp ON glpp.lottery_participation_id = glp.lottery_participation_id AND glpp.participation_prize_no = participationPrizeNo        
			WHERE game_play_id = @newGamePlayID;
			
			UPDATE gaming_client_stats
			SET pending_winning_real=pending_winning_real-pendingAmount,
				current_real_balance=current_real_balance+pendingAmount,
				
				total_wallet_real_won_online =IF(newPayoutTypeId=2,total_wallet_real_won_online, IF(@channelType = 'online', total_wallet_real_won_online + pendingAmount, total_wallet_real_won_online)),
				total_wallet_real_won_retail =IF(newPayoutTypeId=2,total_wallet_real_won_retail, IF(@channelType = 'retail', total_wallet_real_won_retail + pendingAmount, total_wallet_real_won_retail)),
				total_wallet_real_won_self_service = IF(newPayoutTypeId=2,total_wallet_real_won_self_service, IF(@channelType = 'self-service', total_wallet_real_won_self_service + pendingAmount, total_wallet_real_won_self_service)),
				
				total_real_won=total_real_won+pendingAmount,
                total_cash_win=IF(newPayoutTypeId=2, total_cash_win+pendingAmount,total_cash_win),
                total_wallet_real_won=IF(newPayoutTypeId=2, total_wallet_real_won,total_wallet_real_won+pendingAmount)
			WHERE client_stat_id=clientStatID;

			IF (newPayoutTypeId=2) THEN
				SET paymentMethodID=250; -- POS

				CALL TransactionBalanceAccountUpdate(NULL, clientStatID, NULL, NULL, NULL, paymentMethodID, 1, 0, 0, -1, 
					userID, NULL, NULL, 1, 0, 'User', NULL, NULL, NULL, newBalanceAccountID, statusCode);
				
                CALL TransactionCreateManualWithdrawal(clientStatID, paymentMethodID, newBalanceAccountID, pendingAmount, NOW(), 0, NULL, 
					'Physical Pick-Up', NULL, NULL, userID, NULL, 0, balanceManualTransactionID, NULL, 'Lotto-3rdParty', 1, 0,statusCode);
            ELSEIF (newPayoutTypeId=4) THEN
				-- External Payment payout method (CPREQ-128/131)
				-- Changed to External Payments PM for Manual Payment Processing
				SET paymentMethodID=290; -- External Payments

				-- Emulate top-up+manual withdrawal
				CALL TransactionBalanceAccountUpdate(NULL, clientStatID, NULL, NULL, NULL, paymentMethodID, 1, 0, 0, -1, userID, 
					NULL, NULL, 1, 0, 'User', NULL, NULL, NULL, newBalanceAccountID, statusCode);
				CALL TransactionCreateManualWithdrawal(clientStatID, paymentMethodID, newBalanceAccountID, pendingAmount, NOW(), 0, NULL, 'External Payment', NULL, NULL, userID, NULL, 0, balanceManualTransactionID, NULL, 'Lotto-3rdParty',1, 0, statusCode);      
			END IF;
			
			-- Update participation to paid - 2105
			UPDATE gaming_lottery_participations
			SET lottery_participation_status_id=2105
			WHERE lottery_participation_id=participationID;
		END IF;

		IF (statusCode=0) THEN
			UPDATE gaming_pending_winnings
			SET pending_winning_status_id=IFNULL(newStatus,pending_winning_status_id), 
				payout_type_id=IFNULL(newPayoutTypeId,payout_type_id), 
				user_comments=IFNULL(userComments,user_comments),
				date_updated=dateUpdated
			WHERE game_play_id=gamePlayId;

			INSERT INTO gaming_pending_winnings_user_changes(game_play_id,pending_winning_status_id,date_updated,user_id)
			VALUES(gamePlayId,oldStatus,dateUpdated,userID);
          
			-- Update Coupon Status
    	SET newCouponStatus = PropagateCouponStatusFromParticipations(couponID, currentCouponStatus, 0);
    
    	UPDATE gaming_lottery_coupons
    	SET lottery_coupon_status_id=newCouponStatus
    	WHERE gaming_lottery_coupons.lottery_coupon_id=couponID;

			IF (notificationEnabled=1) THEN
				IF (newStatus=3) THEN	
					INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
					VALUES (528,gamePlayId, userID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
				END IF;
				IF (newStatus=1) THEN	
					INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
					VALUES (527,gamePlayId, userID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
				END IF;	
			END IF;
		END IF;
	END IF;
    
END$$

DELIMITER ;

