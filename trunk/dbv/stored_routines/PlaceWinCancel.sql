DROP procedure IF EXISTS `PlaceWinCancel`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceWinCancel`(gamePlayID BIGINT, gameSessionID BIGINT, winToCancelAmount DECIMAL(18, 5), transactionRef VARCHAR(80), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN
	-- First Version 

	DECLARE clientStatID, clientID, currencyID, newGamePlayID, gameRoundID, operatorGameID, gamePlayBetCounterID, betGamePlayID, badDeptGamePlayID, sessionID, gameID BIGINT DEFAULT -1;
	DECLARE betBonusAmount, betRealAmount, betBonusWinLockedAmount,exchangeRate, totalApplicableBonus, badDebt, currentRealBalance, FreeBonusAmount DECIMAL(18,5) DEFAULT 0;
    DECLARE usedBonusMoney, disallowNegativeBalance, playLimitEnabled, realMoneyOnly TINYINT(1) DEFAULT 0;
    DECLARE numBonuses, licenseTypeID, clientWagerTypeID, numTransactions INT DEFAULT 0;

	SET @channelType='online';

	SELECT win.client_stat_id, win.amount_real, win.amount_bonus, win.amount_bonus_win_locked, win.game_round_id, 
		  win.operator_game_id, win.currency_id, bet.game_play_id, ggr.license_type_id, gg.client_wager_type_id, win.round_transaction_no, IFNULL(win.session_id, bet.session_id), gg.game_id
	INTO clientStatID, betRealAmount, betBonusAmount, betBonusWinLockedAmount, gameRoundID, 
		 operatorGameID, currencyID, betGamePlayID, licenseTypeID, clientWagerTypeID, numTransactions, sessionID, gameID
	FROM gaming_game_plays AS win
    STRAIGHT_JOIN gaming_game_rounds AS ggr ON win.game_round_id=ggr.game_round_id
    STRAIGHT_JOIN gaming_games AS gg ON ggr.game_id=gg.game_id
    LEFT JOIN gaming_game_plays AS bet ON bet.game_play_id_win = win.game_play_id AND bet.round_transaction_no=1
	WHERE win.game_play_id=gamePlayID;
    
	IF (clientStatID = -1) THEN 
		SET statusCode = 1; -- could not find game play leave query
        LEAVE root;
	END IF;

	-- First and for most lock player =) we dot need deadlocks!!
	SELECT client_stat_id, current_real_balance
	INTO clientStatID, currentRealBalance
	FROM gaming_client_stats 
	WHERE client_stat_id=clientStatID
	FOR UPDATE;
    
    SELECT value_bool INTO playLimitEnabled FROM gaming_settings WHERE name = 'PLAY_LIMIT_ENABLED';
    SELECT value_bool INTO disallowNegativeBalance FROM gaming_settings WHERE name = 'WAGER_DISALLOW_NEGATIVE_BALANCE';

	SELECT exchange_rate INTO exchangeRate
	FROM gaming_operator_currency 
	STRAIGHT_JOIN gaming_operators ON gaming_operator_currency.currency_id=currencyID AND 
	gaming_operators.is_main_operator AND gaming_operator_currency.operator_id=gaming_operators.operator_id;

	SELECT IFNULL(COUNT(*)>0, 0), IFNULL(SUM(bonus_amount_remaining + current_win_locked_amount), 0)
    INTO usedBonusMoney, totalApplicableBonus
    FROM gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
    STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
    WHERE ggpbi.game_play_id=betGamePlayID;
    
    IF (winToCancelAmount > (currentRealBalance + totalApplicableBonus)) THEN
		SET badDebt = winToCancelAmount - (currentRealBalance + totalApplicableBonus);
    END IF;
        
    IF (usedBonusMoney) THEN
		SET @betRemain=winToCancelAmount;
		SET @bonusCounter=0;
		SET @betReal=0;
		SET @betBonus=0;
		SET @betBonusWinLocked=0;
		SET @freeBetBonus=0;

		INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);
		SET gamePlayBetCounterID=LAST_INSERT_ID();

		INSERT INTO gaming_game_plays_bonus_instances_pre (game_play_bet_counter_id, bonus_instance_id, bet_total, bet_real, bet_bonus, bet_bonus_win_locked, bonus_order, no_loyalty_points)
		SELECT gamePlayBetCounterID, bonus_instance_id, bet_real+free_bet_bonus+bet_bonus+bet_bonus_win_locked AS bet_total, bet_real, bet_bonus+free_bet_bonus, bet_bonus_win_locked, bonus_counter, no_loyalty_points
		FROM
		(
			SELECT
				bonus_instance_id AS bonus_instance_id, 
				@freeBetBonus:=IF(realMoneyOnly, 0, IF(awarding_type='FreeBet', IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining), 0)) AS free_bet_bonus,
				@betRemain:=@betRemain-@freeBetBonus,   
				@betReal:=IF(@bonusCounter=0, IF(currentRealBalance>@betRemain, @betRemain, currentRealBalance), 0) AS bet_real,
				@betRemain:=@betRemain-@betReal,  
				@betBonusWinLocked:=IF(realMoneyOnly, 0, IF(current_win_locked_amount>@betRemain, @betRemain, current_win_locked_amount)) AS bet_bonus_win_locked,
				@betRemain:=@betRemain-@betBonusWinLocked,
				@betBonus:=IF(realMoneyOnly, 0, IF(awarding_type!='FreeBet',IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining),0)) AS bet_bonus,
				@betRemain:=@betRemain-@betBonus, @bonusCounter:=@bonusCounter+1 AS bonus_counter, no_loyalty_points
			FROM
			(
				SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_types_awarding.name AS awarding_type, bonus_amount_remaining, current_win_locked_amount, gaming_bonus_rules.no_loyalty_points
				FROM gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
				STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
				STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
				STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
				STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_wgr_req_weights.bonus_rule_id AND gaming_bonus_rules_wgr_req_weights.operator_game_id=operatorGameID 
                WHERE ggpbi.game_play_id=betGamePlayID
				ORDER BY gaming_bonus_types_awarding.`order` ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id ASC
			) AS XX
			HAVING free_bet_bonus!=0 OR bet_real!=0 OR bet_bonus!=0 OR bet_bonus_win_locked!=0
		) AS XY;


		SELECT IFNULL(COUNT(*),0), SUM(bet_real), SUM(bet_bonus), SUM(bet_bonus_win_locked)
		INTO numBonuses, betRealAmount, betBonusAmount, betBonusWinLockedAmount 
		FROM gaming_game_plays_bonus_instances_pre
		WHERE game_play_bet_counter_id=gamePlayBetCounterID;
        
		IF (badDebt > 0) THEN
			SET betRealAmount = betRealAmount + @betRemain;
		END IF;
        
        SET FreeBonusAmount=0;
		SELECT IFNULL(SUM(bet_bonus),0) INTO FreeBonusAmount 
		FROM gaming_game_plays_bonus_instances_pre 
		JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_pre.bonus_instance_id
		JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
		WHERE game_play_bet_counter_id = gamePlayBetCounterID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);
        
	ELSE  
		SET betRealAmount = winToCancelAmount;
    END IF; 

	UPDATE gaming_client_stats AS gcs
	LEFT JOIN gaming_game_sessions AS ggs ON ggs.game_session_id=gameSessionID
	LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=gcsession.session_id   
	LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
	SET 
		gcs.total_wallet_real_won_online = IF(@channelType = 'online', gcs.total_wallet_real_won_online - winToCancelAmount, gcs.total_wallet_real_won_online),
		gcs.total_wallet_real_won_retail = IF(@channelType = 'retail', gcs.total_wallet_real_won_retail - winToCancelAmount, gcs.total_wallet_real_won_retail),
		gcs.total_wallet_real_won_self_service = IF(@channelType = 'self-service', gcs.total_wallet_real_won_self_service - winToCancelAmount, gcs.total_wallet_real_won_self_service),
		gcs.total_wallet_real_won = gcs.total_wallet_real_won_online + gcs.total_wallet_real_won_retail + gcs.total_wallet_real_won_self_service,
		gcs.total_real_won= IF(@channelType NOT IN ('online','retail','self-service'), gcs.total_real_won-betRealAmount, gcs.total_wallet_real_won + gcs.total_cash_win),

		gcs.current_real_balance=gcs.current_real_balance-betRealAmount, 
		gcs.total_bonus_won=gcs.total_bonus_won-betBonusAmount, gcs.current_bonus_balance=gcs.current_bonus_balance-betBonusAmount, 
		gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won-betBonusWinLockedAmount, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance-betBonusWinLockedAmount, 
		gcs.total_real_won_base=gcs.total_real_won_base-(betRealAmount/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base-((betBonusAmount+betBonusWinLockedAmount)/exchangeRate),

		ggs.total_win=ggs.total_win-winToCancelAmount, ggs.total_win_base=ggs.total_win_base-(winToCancelAmount/exchangeRate), ggs.total_win_real=ggs.total_win_real-betRealAmount, ggs.total_win_bonus=ggs.total_win_bonus-betBonusAmount-betBonusWinLockedAmount,

		gcsession.total_win=gcsession.total_win-winToCancelAmount, gcsession.total_win_base=gcsession.total_win_base-(winToCancelAmount/exchangeRate), gcsession.total_win_real=gcsession.total_win_real-betRealAmount, gcsession.total_win_bonus=gcsession.total_win_bonus-betBonusAmount-betBonusWinLockedAmount,

		gcws.num_wins=gcws.num_wins+IF(winToCancelAmount - badDebt > 0, -1, 0), gcws.total_real_won=gcws.total_real_won-betRealAmount, gcws.total_bonus_won=gcws.total_bonus_won-betBonusAmount-betBonusWinLockedAmount
	WHERE gcs.client_stat_id=clientStatID;  

	
	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, bonus_win_locked_lost, 
     jackpot_contribution, timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, 
     payment_transaction_type_id, is_win_placed, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, round_transaction_no, 
     game_play_message_type_id, license_type_id, pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player, platform_type_id,
     loyalty_points, loyalty_points_after, loyalty_points_bonus, 
     loyalty_points_after_bonus, sign_mult) 
	SELECT winToCancelAmount, (winToCancelAmount/exchangeRate), exchangeRate, betRealAmount, betBonusAmount, betBonusWinLockedAmount, FreeBonusAmount, badDebt, 0, 0, 
     0, NOW(), betGamePlay.game_id, betGamePlay.game_manufacturer_id, betGamePlay.operator_game_id, betGamePlay.client_id, betGamePlay.client_stat_id, betGamePlay.session_id, betGamePlay.game_session_id, betGamePlay.game_round_id, 
     gaming_payment_transaction_type.payment_transaction_type_id, 1, current_real_balance, ROUND(current_bonus_balance+current_bonus_win_locked_balance,0), current_bonus_win_locked_balance, currencyID, numTransactions+1, 
     gaming_game_play_message_types.game_play_message_type_id, betGamePlay.license_type_id, pending_bets_real, pending_bets_bonus, 0, 0, betGamePlay.platform_type_id, 0, gaming_client_stats.current_loyalty_points,0, 
     gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`, -1
	FROM gaming_payment_transaction_type
	JOIN gaming_client_stats ON gaming_payment_transaction_type.name='WinCancelled' AND gaming_client_stats.client_stat_id=clientStatID
    JOIN gaming_game_plays AS betGamePlay ON betGamePlay.game_play_id = gamePlayID
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name='WinCancelled';
    
	SET newGamePlayID=LAST_INSERT_ID();

	CALL GameUpdateRingFencedBalances(clientStatID, newGamePlayID);
         
	UPDATE gaming_game_rounds
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	SET 
		win_total=win_total-winToCancelAmount, win_total_base=ROUND(win_total_base-(winToCancelAmount*exchangeRate),5), win_real=win_real-betRealAmount, win_bonus=win_bonus-betBonusAmount,win_free_bet=win_free_bet-FreeBonusAmount, 
		win_bonus_win_locked=win_bonus_win_locked-betBonusWinLockedAmount, win_bet_diffence_base=win_total_base-bet_total_base,
		balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance,license_type_id = licenseTypeID
	WHERE game_round_id=gameRoundID; 
  
	IF (winToCancelAmount > 0 AND playLimitEnabled) THEN
		SET @licenseType=IF(licenseTypeID=2, 'poker', 'casino');
		CALL PlayLimitsUpdateWithGame(sessionID, clientStatID, @licenseType, -winToCancelAmount, 0, gameID);
	END IF;
  
	IF (usedBonusMoney) THEN 
      
		SET @betBonus=0;
		SET @betBonusWinLocked=0;
		SET @nowWagerReqMet=0;
		SET @hasReleaseBonus=0;
        
		UPDATE gaming_game_plays_bonus_instances AS pbi_update
		JOIN gaming_game_plays_bonus_instances_pre AS BIP ON BIP.game_play_bet_counter_id=gamePlayBetCounterID AND pbi_update.game_play_id=betGamePlayID 
			AND BIP.bonus_instance_id = pbi_update.bonus_instance_id
		JOIN gaming_bonus_instances ON pbi_update.bonus_instance_id=gaming_bonus_instances.bonus_instance_id 
		SET
			pbi_update.win_bonus=IFNULL(pbi_update.win_bonus,0)-BIP.bet_bonus, 
			pbi_update.win_bonus_win_locked=IFNULL(pbi_update.win_bonus_win_locked,0)-BIP.bet_bonus_win_locked, 
			pbi_update.win_real=IFNULL(pbi_update.win_real,0)-BIP.bet_real,
			pbi_update.now_used_all=IF(ROUND(gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount+gaming_bonus_instances.reserved_bonus_funds
			-BIP.bet_bonus-BIP.bet_bonus_win_locked,5)=0, 1, 0);

		IF (ROW_COUNT() > 0) THEN
			UPDATE gaming_game_plays_bonus_instances_pre AS ggpbip 
			STRAIGHT_JOIN gaming_bonus_instances ON ggpbip.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			SET bonus_amount_remaining=bonus_amount_remaining-ggpbip.bet_bonus, current_win_locked_amount=current_win_locked_amount-ggpbip.bet_bonus_win_locked
			WHERE ggpbip.game_play_bet_counter_id=gamePlayBetCounterID;           
		END IF; 
        
	END IF; 
  
    IF (disallowNegativeBalance AND badDebt > 0) THEN
		CALL PlaceTransactionOffsetNegativeBalancePreComputred(clientStatID, badDebt, exchangeRate, newGamePlayID, NULL, NULL, licenseTypeID, badDeptGamePlayID);
	END IF;
  
	CALL PlayReturnData(gamePlayID, gameRoundID, clientStatID , operatorGameID, 0);

	SET gamePlayIDReturned = gamePlayID;
	SET statusCode=0;

END$$

DELIMITER ;

