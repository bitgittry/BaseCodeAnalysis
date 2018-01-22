DROP procedure IF EXISTS `PlaceBetTypeTwoLotto`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBetTypeTwoLotto`(
  couponID BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
	-- Securing the bonus
    -- Added gaming_game_play_message_types
	-- Optimizations: Forcing STRAIGHT_JOINS and INDEXES 
-- Merge To INPH
-- Optimized
 
	DECLARE gamePlayID,gameRoundID, clientStatID, gameManufacturerID BIGINT;
    DECLARE bonusesLeft, wagerStatusCode, licenseTypeID INT DEFAULT 0;
	DECLARE exchangeRate DECIMAL(18,5);

	SELECT gaming_game_plays_lottery.game_play_id, gaming_game_plays.game_round_id, gaming_game_plays.client_stat_id, 
		gaming_game_plays.game_manufacturer_id, MAX(gaming_lottery_participations.lottery_wager_status_id), gaming_lottery_coupons.license_type_id
    INTO gamePlayID, gameRoundID, clientStatID, gameManufacturerID, wagerStatusCode, licenseTypeID
    FROM gaming_game_plays_lottery FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON gaming_game_plays.game_play_id = gaming_game_plays_lottery.game_play_id
	STRAIGHT_JOIN gaming_lottery_coupons FORCE INDEX (PRIMARY) ON gaming_lottery_coupons.lottery_coupon_id=gaming_game_plays_lottery.lottery_coupon_id
	STRAIGHT_JOIN gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id) ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
    STRAIGHT_JOIN gaming_lottery_participations FORCE INDEX (lottery_dbg_ticket_id) ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_lottery_participations.lottery_dbg_ticket_id
    WHERE gaming_game_plays_lottery.lottery_coupon_id = couponID;
    
	-- If Wager Status Code is FundsReserved Skip Validation
    IF (wagerStatusCode != 3) THEN
		IF (wagerStatusCode = 5) THEN
			CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, 0);
			CALL PlayReturnBonusInfoOnBet(gamePlayID);
			SET statusCode = 100;
			LEAVE root;
		ELSE 
			SET statusCode = 1;
			LEAVE root;
		END IF;
	 END IF;

	SELECT exchange_rate into exchangeRate 
	FROM gaming_client_stats
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
	WHERE gaming_client_stats.client_stat_id=clientStatID
	LIMIT 1;

	UPDATE gaming_lottery_dbg_tickets FORCE INDEX (lottery_coupon_id)
    STRAIGHT_JOIN gaming_lottery_participations ON gaming_lottery_participations.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id AND gaming_lottery_participations.lottery_wager_status_id = 3
    SET gaming_lottery_participations.lottery_wager_status_id = 5
    WHERE gaming_lottery_dbg_tickets.lottery_coupon_id = couponID;
    
    UPDATE gaming_lottery_coupons
    SET gaming_lottery_coupons.lottery_wager_status_id = 5, lottery_coupon_status_id = 2102
    WHERE gaming_lottery_coupons.lottery_coupon_id = couponID;

	UPDATE gaming_game_plays_bonus_instances 
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
	SET 
		is_secured=IF(now_wager_requirement_met=1 AND transfer_type.name!='NonReedemableBonus',1,is_secured),
		is_freebet_phase=IF(now_wager_requirement_met=1 AND transfer_type.name='NonReedemableBonus',1,is_freebet_phase),
		secured_date=IF(now_wager_requirement_met=1 AND transfer_type.name!='NonReedemableBonus',NOW(),NULL),
		gaming_bonus_instances.is_active=IF(gaming_bonus_instances.is_active=0,0,IF((now_wager_requirement_met=1 AND transfer_type.name!='NonReedemableBonus'),0,1))
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;  
    
	UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id) 
	STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
	SET 
		ggpbi.bonus_transfered_total=(
        CASE transfer_type.name
			WHEN 'All' THEN bonus_amount_remaining+current_win_locked_amount
			WHEN 'Bonus' THEN bonus_amount_remaining
			WHEN 'BonusWinLocked' THEN current_win_locked_amount
			WHEN 'UpToBonusAmount' THEN LEAST(bonus_amount_given, bonus_amount_remaining+current_win_locked_amount)
			WHEN 'UpToPercentage' THEN LEAST(bonus_amount_given*transfer_upto_percentage, bonus_amount_remaining+current_win_locked_amount)
			WHEN 'ReleaseBonus' THEN LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, bonus_amount_remaining+current_win_locked_amount)
			WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
			WHEN 'NonReedemableBonus' THEN current_win_locked_amount
			ELSE 0
		END),
		ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked' OR transfer_type.name='NonReedemableBonus', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)),
		ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
		bonus_transfered_lost=IF(transfer_type.name!='NonReedemableBonus',bonus_amount_remaining-bonus_transfered,0),
		bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
		ring_fenced_transfered = current_ring_fenced_amount,
		bonus_amount_remaining=IF(transfer_type.name!='NonReedemableBonus',0,bonus_amount_remaining),
		current_win_locked_amount=0, current_ring_fenced_amount=0,  
		gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total
	WHERE ggpbi.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

	-- BonusRequirementMet
	SET @requireTransfer=0;

	SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
	INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
	FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

	SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
	SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
	IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
		CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino ,@ringFencedAmountPoker, NULL);
	END IF; 

	-- BonusCashExchange
	UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id) 
	STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
		gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
	SET 
		ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))* -- number of transfers achieved
		gaming_bonus_instances.transfer_every_amount, -- amount to transfer each time
		bonus_amount_remaining+current_win_locked_amount), -- cannot transfer more than the bonus remaining value
		ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
		ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
		bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  -- update ggpbi
		gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
		gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total
	WHERE ggpbi.game_play_id=gamePlayID AND ggpbi.now_release_bonus=1 AND ggpbi.now_used_all=0 AND ggpbi.now_wager_requirement_met=0;

	SET @requireTransfer=0;

	SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
	INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
	FROM gaming_game_plays_bonus_instances
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
	WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

	SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
	SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;

	IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
		CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino ,@ringFencedAmountPoker, NULL);
	END IF; 

    SELECT COUNT(1) AS numBonuses INTO bonusesLeft
	FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
	WHERE gaming_bonus_instances.client_stat_id=clientStatID AND is_active AND is_freebet_phase=0
	GROUP BY client_stat_id;

	UPDATE gaming_client_stats SET bet_from_real=IF(IFNULL(bonusesLeft,0)=0,0,bet_from_real) WHERE client_stat_id = clientStatID;  

    
  IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 THEN
      INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
  END IF;
    
	UPDATE gaming_game_plays SET is_processed=0 WHERE game_play_id=gamePlayID;

	CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, 0);
    CALL PlayReturnBonusInfoOnBet(gamePlayID);
	CALL NotificationEventCreate(CASE licenseTypeID WHEN 6 THEN 550	WHEN 7 THEN 560 END, couponID, clientStatID, 0);

	SET statusCode =0;
    
END$$

DELIMITER ;

