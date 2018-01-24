DROP procedure IF EXISTS `PlayerUpdateVIPLevelAfterRefund`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateVIPLevelAfterRefund`(clientStatID BIGINT)
root : BEGIN                  
                  
  -- this store procedure is called after the sp ReturnFundsTypeTwoLotto instead of the sp PlayerUpdateVIPLevel
  -- this sp revert the VIP level even if the current one is manual (level wrongly obtained)
  --  only one manual level can be downgrade, infact if they are two or more at least one has been stepped manually by an operator
  
	DECLARE lifetimeLP, periodLP, LPForCheck, LPToAward, LPToRemove, LPToRemoveOnReturnFunds, LPToUpgradeCurrentLevel, newPeriodLP, LPToUpgradeUpdLevel, curLPAmountTotal DECIMAL(18,5);
	DECLARE clientID, curVipLevel, curVipLevelID, curLevelMinVip, curLevelMaxVip, curVipLevelOrder, maxVipLevelID, maxVipLevelMinLevel,
 			maxVipLevelOrder, updVipLevelID, updVipLevel, updVipLevelOrder, updManualLevelID, updManualLevelMinLevel, updManualLevelOrder, CtVipLevelID BIGINT;
	DECLARE curVipLevelType VARCHAR(100);
	DECLARE periodToAdd,maxVipLevelPeriod,numVipLevels INT;
	DECLARE updVipLevelIsManual, isNewPlayer TINYINT(1) DEFAULT 0;

  	SET @@SESSION.max_sp_recursion_depth = 1;

	SELECT vip_level_id , min_vip_level, period_in_days, `order`
	INTO maxVipLevelID, maxVipLevelMinLevel, maxVipLevelPeriod, maxVipLevelOrder
	FROM gaming_vip_levels
	ORDER BY min_vip_level DESC LIMIT 1;

	SELECT gcs.client_id, gcs.total_loyalty_points_given, gcs.loyalty_points_running_total, gc.vip_level, gc.vip_level_id, gvl.min_vip_level, gvl.max_vip_level, gvl.set_type, gvl.`order`, gvl.max_loyalty_points
    INTO clientID, lifetimeLP, periodLP, curVipLevel, curVipLevelID, curLevelMinVip, curLevelMaxVip, curVipLevelType, curVipLevelOrder, LPToUpgradeCurrentLevel
	FROM gaming_client_stats  gcs
	JOIN gaming_clients gc ON gc.client_id = gcs.client_id
	LEFT JOIN gaming_vip_levels gvl ON gc.vip_level_id = gvl.vip_level_id
	WHERE gcs.client_stat_id = clientStatID;

	-- If there are no vip levels reset player level and id
    SELECT COUNT(*) INTO numVipLevels FROM gaming_vip_levels;
    
	IF (numVipLevels=0) THEN
		UPDATE gaming_clients	
		SET vip_level = 0, vip_level_id = null
		WHERE client_id = clientID;

		LEAVE root;
	END IF;

	-- If player has no assigned level id then he is new
	IF (curVipLevelID IS NULL) then	
		SET isNewPlayer=1;
	END IF;

	-- Check if the player is new and imported from an other system with VIP Level
	-- Assign the correct VIP Level ID but do not give any award
	IF (isNewPlayer=1 AND curVipLevel>0) THEN
		UPDATE gaming_clients 
		JOIN 
		(
			SELECT vip_level_id , clientID AS client_id
			FROM gaming_vip_levels
			WHERE (curVipLevel >= min_vip_level AND curVipLevel <= IFNULL(max_vip_level, 9999999999)) OR (maxVipLevelMinLevel <= curVipLevel)
			ORDER BY min_vip_level DESC LIMIT 1
		) gvl ON gvl.client_id = gaming_clients.client_id
		SET gaming_clients.vip_level_id = IF(gvl.vip_level_id IS NULL, maxVipLevelID, gvl.vip_level_id)
		WHERE gaming_clients.client_id = clientID;

		LEAVE root;
	END IF;

	IF (curVipLevelType='LoyaltyPointsLifeTime' or curVipLevelType='Manual') THEN
		SET LPForCheck = lifetimeLP;
	ELSEIF(curVipLevelType='LoyaltyPointsPeriod') THEN
		SET LPForCheck = periodLP;
	ELSEIF(curVipLevelType IS NULL) THEN
		SET curVipLevelType=NULL; 

	END IF;


	  --  if the current lp amount doesn't fit with any of the ranges the closer upper minimum limit is taken
	  IF IFNULL(LPForCheck,0)>0 THEN
		IF ((select count(*) FROM gaming_vip_levels WHERE LPForCheck BETWEEN min_loyalty_points AND max_loyalty_points)=0) THEN
		  SELECT min(min_loyalty_points) INTO LPForCheck FROM gaming_vip_levels WHERE min_loyalty_points>LPForCheck;
		END IF;
	  END IF;


	SELECT vip_level_id, min_vip_level, period_in_days, `order` INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder
	FROM gaming_vip_levels gvl
	WHERE CASE 
		WHEN curVipLevelType in ('LoyaltyPointsLifeTime','Manual') THEN LPForCheck BETWEEN min_loyalty_points AND IFNULL(gvl.max_loyalty_points, 99999999999) 
		WHEN curVipLevelType='LoyaltyPointsPeriod' THEN gvl.min_loyalty_points IS NOT NULL AND LPForCheck >= 
				(SELECT SUM(max_loyalty_points) FROM gaming_vip_levels WHERE `order` <= gvl.`order` AND `order` > curVipLevelOrder)			
		WHEN curVipLevelType IS NULL THEN IF(LPForCheck IS NULL,0,LPForCheck) BETWEEN min_loyalty_points AND IFNULL(gvl.max_loyalty_points, 99999999999) OR
			(curVipLevel >= min_vip_level AND curVipLevel <= IFNULL(max_vip_level, 9999999999))
			END	
	ORDER BY `order` DESC LIMIT 1;

	IF(curVipLevel=0 AND LPForCheck IS NULL AND updVipLevelID=maxVipLevelID) THEN
		SELECT vip_level_id , min_vip_level, period_in_days, `order`
		INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder
		FROM gaming_vip_levels
		ORDER BY `order` ASC LIMIT 1;
	END IF;

	-- Player is not eligible to upgrade
	IF (updVipLevelID IS NULL AND curVipLevelType='LoyaltyPointsPeriod' AND periodLP < LPToUpgradeCurrentLevel) THEN
		LEAVE root;
	ELSEIF (updVipLevelID IS NULL AND curVipLevelType='LoyaltyPointsPeriod' AND periodLP > LPToUpgradeCurrentLevel) THEN
		SELECT vip_level_id, min_vip_level, period_in_days, `order` INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder	
		FROM gaming_vip_levels gvl
		WHERE gvl.`order`=curVipLevelOrder+1;
	END IF;

	-- Player reached maximum level
	IF (updVipLevelID IS NULL AND NOT curVipLevelType IS NULL) THEN
		/* the player has overpass the max level so we must update him to maxLevelID */
		SET updVipLevelID=maxVipLevelID;
		SET updVipLevel=maxVipLevelMinLevel;
		SET	periodToAdd= IF(maxVipLevelPeriod IS NULL, 365, maxVipLevelPeriod);
		SET updVipLevelOrder=maxVipLevelOrder;
	END IF;

	-- Player does not meet criteria to change VIP Level
	IF (updVipLevelID=curVipLevelID OR (curVipLevelType='LoyaltyPointsPeriod' AND updVipLevelOrder <= curVipLevelOrder)) THEN
		LEAVE root;
	END IF;




	-- Check if there is any manual level between the levels that the player must upgrade
	SELECT vip_level_id, min_vip_level, `order`
	INTO updManualLevelID, updManualLevelMinLevel, updManualLevelOrder
	FROM gaming_vip_levels
	WHERE `order` BETWEEN IFNULL(curVipLevelOrder,0) AND updVipLevelOrder AND set_type='Manual'
	ORDER BY `order` LIMIT 1;
  
  -- only one manual level can be downgraded, if they are two, this means that one was stepped manually by the operator and cannot be reverted
	SELECT count(vip_level_id)
	INTO CtVipLevelID
	FROM gaming_vip_levels
	WHERE `order` BETWEEN IFNULL(updVipLevelOrder,0) and IFNULL(curVipLevelOrder,0)  AND set_type='Manual';

  IF (CtVipLevelID>1) THEN
    LEAVE root;
  END IF;
  
  -- insert into _log (text) select cast(CtVipLevelID as char);
  
  
	-- Player must not pass automatically manual levels
	IF (updManualLevelID IS NOT NULL AND updManualLevelID <> updVipLevelID) THEN
		SET updVipLevelID=updManualLevelID;
		SET updVipLevel=updManualLevelMinLevel;
		SET periodToAdd=365;
		SET updVipLevelOrder=updManualLevelOrder;
		SET updVipLevelIsManual=1;
	END IF;

	-- LPToAward, LPToRemove Calculate how many points he must be awarded and how many must be removed from running points
	SELECT SUM(max_loyalty_points) 
	INTO LPToRemove
	FROM gaming_vip_levels
	WHERE `order` >= curVipLevelOrder AND `order` < updVipLevelOrder;

	SELECT SUM(achievement_points_reward) 
	INTO LPToRemoveOnReturnFunds
	FROM gaming_vip_levels
	WHERE `order` > updVipLevelOrder AND `order` <=  curVipLevelOrder;

	IF ((curVipLevelOrder IS NULL OR curVipLevelType IS NULL) AND isNewPlayer=1) THEN
		SELECT `order`, set_type INTO curVipLevelOrder, curVipLevelType FROM gaming_vip_levels WHERE vip_level_id=updVipLevelID;
	END IF;

	SELECT SUM(achievement_points_reward) 
	INTO LPToAward
	FROM gaming_vip_levels
	WHERE CASE 
			WHEN curVipLevelOrder=updVipLevelOrder AND isNewPlayer=1 THEN `order` = curVipLevelOrder
			ELSE `order` > curVipLevelOrder AND `order` <= updVipLevelOrder
		  END;

	IF (updVipLevelIsManual=0) THEN
		SELECT CASE WHEN set_type='Manual' THEN 1 ELSE 0 END
		INTO updVipLevelIsManual
		FROM gaming_vip_levels
		WHERE vip_level_id = updVipLevelID;
	END IF;

	-- Update client vip level id and vip level
	UPDATE gaming_clients
	SET vip_level = IFNULL(updVipLevel,0), vip_level_id = IFNULL(updVipLevelID,0)
	WHERE client_id = clientID;

	-- Update client total and running lp
	UPDATE gaming_client_stats 
	SET loyalty_points_reset_date = IF(curVipLevelType = 'LoyaltyPointsPeriod', DATE_FORMAT(DATE(DATE_ADD(NOW(), INTERVAL periodToAdd DAY)), "%Y-%m-%d 23:59:59"), loyalty_points_reset_date),
		loyalty_points_running_total = IF(curVipLevelType = 'LoyaltyPointsPeriod', periodLP+IFNULL(LPToAward,0)-IFNULL(LPToRemove,0) -IFNULL(LPToRemoveOnReturnFunds,0), loyalty_points_running_total), 
		total_loyalty_points_given = total_loyalty_points_given + IFNULL(LPToAward,0)-IFNULL(LPToRemoveOnReturnFunds,0),
		current_loyalty_points = current_loyalty_points + IFNULL(LPToAward,0)-IFNULL(LPToRemoveOnReturnFunds,0)
	WHERE client_id = clientID;

	SELECT amount_total
	INTO curLPAmountTotal
	FROM gaming_clients_loyalty_points_transactions
	WHERE client_id=clientID
	ORDER BY loyalty_points_transaction_id DESC LIMIT 1;
	
	-- Update lp transaction
	INSERT INTO gaming_clients_loyalty_points_transactions (client_id,time_stamp,amount,amount_total) 
	SELECT clientID, NOW(), IFNULL(achievement_points_reward,0), IF(curLPAmountTotal IS NULL,IFNULL(achievement_points_reward,0),curLPAmountTotal+IFNULL(achievement_points_reward,0))
	FROM gaming_vip_levels
	WHERE `order` > curVipLevelOrder AND `order` <= updVipLevelOrder;

	-- Update game plays
	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, amount_other, bonus_lost, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, currency_id, sign_mult,loyalty_points, loyalty_points_bonus,loyalty_points_after, loyalty_points_after_bonus, is_win_placed) 
	SELECT 0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), clientID, clientStatID, gptt.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus, currency_id, 1,IFNULL(gvl.achievement_points_reward,0),0,gcs.current_loyalty_points,IFNULL(gcs.total_loyalty_points_given_bonus - gcs.total_loyalty_points_used_bonus,0), 0
	FROM gaming_payment_transaction_type gptt
	JOIN gaming_client_stats gcs ON gcs.client_stat_id=clientStatID
	JOIN (SELECT * FROM gaming_vip_levels WHERE vip_level_id > curVipLevelOrder AND vip_level_id <= updVipLevelOrder) gvl
	WHERE gptt.name = 'LoyaltyPointsProgression';

	-- Check if the new lp running is enough to upgrade to next levelunless the update level is already manual
	IF(updVipLevelIsManual=0) THEN
		SELECT gvl.max_loyalty_points
		INTO LPToUpgradeUpdLevel
		FROM gaming_vip_levels gvl
		JOIN gaming_vip_levels gvl_next ON gvl.`order`+1 = gvl_next.`order`
		WHERE gvl.vip_level_id = updVipLevelID;
		
		SELECT CASE WHEN curVipLevelType='LoyaltyPointsLifeTime' THEN total_loyalty_points_given
					ELSE loyalty_points_running_total END
		INTO newPeriodLP
		FROM gaming_client_stats
		WHERE client_stat_id= clientStatID;

		-- We must updagre player one more level
		IF (LPToUpgradeUpdLevel <= newPeriodLP) then
			CALL PlayerUpdateVIPLevel(clientStatID);
		END IF;
	END IF;
 
END root$$

DELIMITER ;

