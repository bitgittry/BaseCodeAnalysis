DROP procedure IF EXISTS `PlayerUpdateVIPLevel`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateVIPLevel`(clientStatID bigint, isReturn TINYINT)
root: BEGIN

	-- Brian: Solved Bug of inserting a transaction in gaming_game_plays even if player doesn't progresses vip level 

	DECLARE lifetimeLP, periodLP, LPForCheck, LPToAward, LPToRemove,LPToAwardOnReturnFunds, LPToRemoveOnReturnFunds, 
		LPToUpgradeCurrentLevel, newPeriodLP, LPToUpgradeUpdLevel, LPToDowngradeUpdLevel, curLPAmountTotal, LPToAwardNet decimal(18, 5);    
    DECLARE clientID, curVipLevel, curVipLevelID, curLevelMinVip, curLevelMaxVip, curVipLevelOrder, maxVipLevelID, 
		maxVipLevelMinLevel, maxVipLevelOrder, minVipLevelID, minVipLevelMinLevel, minVipLevelOrder,updVipLevelID, updVipLevel, updVipLevelOrder, updManualLevelID, 
        updManualLevelMinLevel, updManualLevelOrder, CtVipLevelID bigint;
    DECLARE curVipLevelType varchar(100);
    DECLARE periodToAdd, maxVipLevelPeriod,minVipLevelPeriod, numVipLevels int;
    DECLARE updVipLevelIsManual, isNewPlayer, matchAnyVipLevel, vipProgressionNow tinyint(1) DEFAULT 0; 

  SET @@SESSION.max_sp_recursion_depth = 3; 

    SELECT
      gaming_vip_levels.vip_level_id,
      min_vip_level,
      period_in_days,
      `order` INTO maxVipLevelID, maxVipLevelMinLevel, maxVipLevelPeriod, maxVipLevelOrder
    FROM gaming_vip_levels
    ORDER BY max_vip_level DESC LIMIT 1;

   SELECT
      gaming_vip_levels.vip_level_id,
      min_vip_level,
      period_in_days,
      `order` INTO minVipLevelID, minVipLevelMinLevel, minVipLevelPeriod, minVipLevelOrder
    FROM gaming_vip_levels
    ORDER BY max_vip_level LIMIT 1;

    SELECT
      gcs.client_id,
      gcs.total_loyalty_points_given,
      gcs.loyalty_points_running_total,
      gc.vip_level,
      gc.vip_level_id,
      gvl.min_vip_level,
      gvl.max_vip_level,
      gvl.set_type,
      gvl.`order`,
      gvl.max_loyalty_points 
    INTO clientID, lifetimeLP, periodLP, curVipLevel, curVipLevelID, 
		curLevelMinVip, curLevelMaxVip, curVipLevelType, curVipLevelOrder, LPToUpgradeCurrentLevel
    FROM gaming_client_stats gcs
	STRAIGHT_JOIN gaming_clients gc ON gc.client_id = gcs.client_id
	LEFT JOIN gaming_vip_levels gvl ON gc.vip_level_id = gvl.vip_level_id
    WHERE gcs.client_stat_id = clientStatID;
    
    IF (curVipLevelType IS NULL) THEN
		SELECT gvl.set_type
        INTO curVipLevelType
        FROM gaming_vip_levels gvl
        ORDER BY min_vip_level ASC LIMIT 1;
        
        IF (curVipLevelType != 'LoyaltyPointsLifeTime') THEN
			SET curVipLevelType = NULL;
		END IF;
    END IF;

    -- If there are no vip levels reset player level and id
    SELECT COUNT(*) INTO numVipLevels
    FROM gaming_vip_levels;

    IF (numVipLevels = 0) THEN
      UPDATE gaming_clients
      SET gaming_clients.vip_level = 0,
          gaming_clients.vip_level_id = NULL
      WHERE client_id = clientID;

      LEAVE root;
    END IF;

    -- If player has no assigned level id then he is new
    IF (curVipLevelID IS NULL) THEN
      SET isNewPlayer = 1;
    END IF;

    -- Check if the player is new and imported from an other system with VIP Level
    -- Assign the correct VIP Level ID but do not give any award
    IF (isNewPlayer = 1 AND curVipLevel > 0) THEN
      
      UPDATE 
      (
			SELECT gaming_vip_levels.vip_level_id, clientID AS client_id
			FROM gaming_vip_levels
			WHERE (curVipLevel >= min_vip_level
				AND curVipLevel <= IFNULL(max_vip_level, 9999999999)) OR (maxVipLevelMinLevel <= curVipLevel)
			ORDER BY min_vip_level DESC LIMIT 1
	  ) AS gvl
      JOIN gaming_clients ON gaming_clients.client_id=gvl.client_id
      SET gaming_clients.vip_level_id = IF(gvl.vip_level_id IS NULL, maxVipLevelID, gvl.vip_level_id)
      WHERE gaming_clients.client_id = clientID;

      LEAVE root;
    END IF;

    IF(curVipLevelType IN ('LoyaltyPointsLifeTime', 'Manual')) THEN
      SET LPForCheck = lifetimeLP;
    ELSEIF (curVipLevelType = 'LoyaltyPointsPeriod') THEN
      SET LPForCheck = periodLP;
   -- ELSEIF(curVipLevelType='Manual') THEN
   --   SET LPForCheck = lifetimeLP; -- To Be Checked
    ELSEIF (curVipLevelType IS NULL) THEN
      SET curVipLevelType = NULL;
  	ELSE -- Manual
     	LEAVE root;
    END IF;

    --  if the current lp amount doesn't fit with any of the ranges the closer upper minimum limit is taken
    IF IFNULL(LPForCheck, 0) > 0 THEN
      
		SELECT COUNT(*) > 0 INTO matchAnyVipLevel
		FROM gaming_vip_levels
		WHERE LPForCheck BETWEEN min_loyalty_points AND IFNULL(max_loyalty_points, 1000000000000);
      
		IF (matchAnyVipLevel = 0) THEN 
              
			SELECT min_loyalty_points INTO LPForCheck
			FROM gaming_vip_levels
			WHERE min_loyalty_points >= LPForCheck 
            ORDER BY min_loyalty_points ASC
            LIMIT 1;
			 
		END IF;
     
    END IF; -- IF IFNULL(LPForCheck, 0) > 0 THEN


    IF (curVipLevelType IN ('LoyaltyPointsLifeTime', 'Manual')) THEN
	
		SELECT
		  gvl.vip_level_id,
		  min_vip_level,
		  period_in_days,
		  `order` INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder
		FROM gaming_vip_levels gvl
		  WHERE LPForCheck BETWEEN min_loyalty_points AND IFNULL(gvl.max_loyalty_points, 99999999999)
		ORDER BY `order` DESC LIMIT 1;
    	
    ELSEIF (curVipLevelType = 'LoyaltyPointsPeriod' AND NOT isReturn) THEN 
	
		SELECT
		  gvl.vip_level_id,
		  min_vip_level,
		  period_in_days,
		  `order` INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder
		FROM gaming_vip_levels gvl
		WHERE	gvl.min_loyalty_points IS NOT NULL  
				AND  LPForCheck BETWEEN min_loyalty_points AND IFNULL(gvl.max_loyalty_points, 99999999999)
		ORDER BY `order` DESC 
		LIMIT 1;

    ELSEIF (curVipLevelType = 'LoyaltyPointsPeriod' AND isReturn) THEN 
  
		  SELECT
			gvl.vip_level_id,
			min_vip_level,
			period_in_days,
			`order` INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder
			FROM gaming_vip_levels gvl
			WHERE	gvl.min_loyalty_points IS NOT NULL AND 
					LPForCheck <=  
					(
						SELECT SUM(min_loyalty_points)
						FROM gaming_vip_levels
						WHERE `order` <= curVipLevelOrder
					)
			ORDER BY `order` 
			LIMIT 1;
			
    END IF;

    IF (curVipLevelType IS NULL) THEN 
		  SELECT
			gvl.vip_level_id,
			min_vip_level,
			period_in_days,
			`order` INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder
		  FROM gaming_vip_levels gvl
			WHERE		IF(LPForCheck IS NULL, 0, LPForCheck) BETWEEN min_loyalty_points AND IFNULL(gvl.max_loyalty_points, 99999999999)
				OR (curVipLevel >= min_vip_level AND curVipLevel <= IFNULL(max_vip_level, 9999999999)) 
		  ORDER BY `order` DESC LIMIT 1;
    END	IF;

    IF (curVipLevel = 0 AND LPForCheck IS NULL AND updVipLevelID = maxVipLevelID) THEN
      
      SELECT
        gaming_vip_levels.vip_level_id, min_vip_level, period_in_days, `order` 
	  INTO updVipLevelID, updVipLevel, periodToAdd, updVipLevelOrder
      FROM gaming_vip_levels
      ORDER BY `order` ASC LIMIT 1;
    END IF;

    -- Player reached maximum level
    IF (updVipLevelID IS NULL AND NOT curVipLevelType IS NULL) THEN
    
    /* the player has overpass the max level so we must update him to maxLevelID */
      SET updVipLevelID = maxVipLevelID;
      SET updVipLevel = maxVipLevelMinLevel;
      SET periodToAdd = IF(maxVipLevelPeriod IS NULL, 365, maxVipLevelPeriod);
      SET updVipLevelOrder = maxVipLevelOrder;
    
    END IF;

    /* Merged from PlayerUpdateVIPLevelAfterRefund SP */
    -- Check if there is any manual level between the levels that the player must upgrade
    SELECT
      gaming_vip_levels.vip_level_id,
      min_vip_level,
      `order` INTO updManualLevelID, updManualLevelMinLevel, updManualLevelOrder
    FROM gaming_vip_levels
    WHERE `order` BETWEEN IFNULL(curVipLevelOrder, 0) AND updVipLevelOrder
    AND set_type = 'Manual'
    ORDER BY `order` LIMIT 1;

    -- only one manual level can be downgraded, if they are two, this means that one was stepped manually by the operator and cannot be reverted
    SELECT
      COUNT(gaming_vip_levels.vip_level_id) INTO CtVipLevelID
    FROM gaming_vip_levels
    WHERE `order` BETWEEN IFNULL(updVipLevelOrder, 0) AND IFNULL(curVipLevelOrder, 0)
    AND set_type = 'Manual';

    IF (CtVipLevelID > 1) THEN
    
      LEAVE root;
      
    END IF;

    -- Player must not pass automatically manual levels
    IF (updManualLevelID IS NOT NULL AND updManualLevelID <> updVipLevelID) THEN

      SET updVipLevelID = updManualLevelID;
      SET updVipLevel = updManualLevelMinLevel;
      SET periodToAdd = 365;
      SET updVipLevelOrder = updManualLevelOrder;
      SET updVipLevelIsManual = 1;

    END IF;

    -- LPToAward, LPToRemove Calculate how many points he must be awarded and how many must be removed from running points
    IF ((curVipLevelOrder IS NULL
      OR curVipLevelType IS NULL)
      AND isNewPlayer = 1) THEN
      SELECT
        `order`,
        set_type INTO curVipLevelOrder, curVipLevelType
      FROM gaming_vip_levels
      WHERE vip_level_id = updVipLevelID;
    END IF;


 -- LPToAward, LPToRemove Calculate how many points he must be awarded and how many must be removed from running points
	SELECT SUM(achievement_points_reward) INTO LPToAward
    FROM gaming_vip_levels
    WHERE CASE WHEN curVipLevelOrder = updVipLevelOrder AND
        isNewPlayer = 1 THEN `order` = curVipLevelOrder ELSE `order` > curVipLevelOrder
        AND `order` <= updVipLevelOrder END;

    SELECT SUM(max_loyalty_points) INTO LPToRemove
    FROM gaming_vip_levels
    WHERE `order` >= curVipLevelOrder
    AND `order` < updVipLevelOrder;
  
  -- if SP is called after Return Funds has been made
    IF (isReturn=1) THEN
		
		SELECT SUM(achievement_points_reward) INTO LPToRemoveOnReturnFunds
		FROM gaming_vip_levels
		WHERE `order` <= curVipLevelOrder AND `order` > updVipLevelOrder;

		SELECT SUM(max_loyalty_points) INTO LPToAwardOnReturnFunds
		FROM gaming_vip_levels 
		WHERE `order` < curVipLevelOrder AND `order` >= updVipLevelOrder;
       
	END IF;
	   
	IF (updVipLevelIsManual = 0) THEN
		  SELECT
			CASE WHEN set_type = 'Manual' THEN 1 ELSE 0 END INTO updVipLevelIsManual
		  FROM gaming_vip_levels
		  WHERE vip_level_id = updVipLevelID;
	END IF;

    -- Update client total and running lp
    UPDATE gaming_client_stats
    SET loyalty_points_reset_date = IF(curVipLevelType = 'LoyaltyPointsPeriod', DATE_FORMAT(DATE(DATE_ADD(NOW(), INTERVAL periodToAdd DAY)), "%Y-%m-%d 23:59:59"), loyalty_points_reset_date),
        loyalty_points_running_total = IF(curVipLevelType = 'LoyaltyPointsPeriod', periodLP + IFNULL(LPToAward, 0) - IFNULL(LPToRemove, 0)+ IFNULL(LPToAwardOnReturnFunds,0) - IFNULL(LPToRemoveOnReturnFunds, 0), loyalty_points_running_total),
        total_loyalty_points_given = total_loyalty_points_given + IFNULL(LPToAward, 0) - IFNULL(LPToRemoveOnReturnFunds, 0),
        current_loyalty_points = current_loyalty_points + IFNULL(LPToAward, 0) - IFNULL(LPToRemoveOnReturnFunds,0)
    WHERE client_stat_id = clientStatID;
    
	SET LPToAwardNet = IFNULL(LPToAward, 0) - IFNULL(LPToRemoveOnReturnFunds, 0);

	IF (updVipLevelID != IFNULL(curVipLevelID, 0)) THEN
   
		-- Update client vip level id and vip level
		UPDATE gaming_clients
		SET vip_level = IFNULL(GREATEST(
				IFNULL(IF(IFNULL(vip_level_id, updVipLevelID) = updVipLevelID, curVipLevel, 0), 0), updVipLevel), vip_level),
			vip_level_id = IFNULL(updVipLevelID, 0)
		WHERE client_id = clientID;

		IF (LPToAwardNet != 0) THEN
        
			-- Update lp transaction
			INSERT INTO gaming_clients_loyalty_points_transactions (client_id, time_stamp, amount, amount_total, reason)
			SELECT client_id, NOW(), LPToAwardNet, current_loyalty_points, 'Loyalty Points Progression'
			FROM gaming_client_stats
			WHERE client_stat_id=clientStatID;

			-- Update game plays
			INSERT INTO gaming_game_plays (amount_total, amount_total_base, exchange_rate, amount_real, 
				amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, timestamp, client_id, client_stat_id, 
				payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
				pending_bet_real, pending_bet_bonus, currency_id, sign_mult, 
				loyalty_points, loyalty_points_bonus, loyalty_points_after, loyalty_points_after_bonus, is_win_placed)
			  SELECT
					   0,
					   0,
					   0,
					   0,
					   0,
					   0,
					   0,
					   0,
					   0,
					   NOW(),
					   clientID,
					   clientStatID,
					   gptt.payment_transaction_type_id,
					   current_real_balance,
					   current_bonus_balance + current_bonus_win_locked_balance,
					   current_bonus_win_locked_balance,
					   pending_bets_real,
					   pending_bets_bonus,
					   currency_id,
					   1,
					   LPToAwardNet,
					   0,
					   gcs.current_loyalty_points,
					   IFNULL(gcs.total_loyalty_points_given_bonus - gcs.total_loyalty_points_used_bonus, 0),
					   0
			FROM gaming_payment_transaction_type gptt
			JOIN gaming_client_stats gcs ON gcs.client_stat_id = clientStatID
			WHERE gptt.NAME = 'LoyaltyPointsProgression';
			
        END IF;
        
	END IF;

    -- Check if the new lp running is enough to upgrade to next level, unless the update level is already manual
    IF (updVipLevelIsManual = 0) THEN
      SELECT
        gvl.max_loyalty_points INTO LPToUpgradeUpdLevel
      FROM gaming_vip_levels gvl
        JOIN gaming_vip_levels gvl_next
          ON gvl.`order` + 1 = gvl_next.`order`
      WHERE gvl.vip_level_id = updVipLevelID;
    END IF;

    IF (updVipLevelIsManual = 0) THEN
      SELECT
        gvl.max_loyalty_points INTO LPToDowngradeUpdLevel
      FROM gaming_vip_levels gvl
        JOIN gaming_vip_levels gvl_next
          ON gvl.`order` - 1 = gvl_next.`order`
      WHERE gvl.vip_level_id = updVipLevelID;
    END IF;

    SELECT
      CASE WHEN curVipLevelType = 'LoyaltyPointsLifeTime' THEN total_loyalty_points_given ELSE loyalty_points_running_total END INTO newPeriodLP
    FROM gaming_client_stats
    WHERE client_stat_id = clientStatID;

  -- We must upgrade player one more level
  IF (LPToUpgradeUpdLevel < newPeriodLP AND matchAnyVipLevel) THEN
		CALL PlayerUpdateVIPLevel(clientStatID, isReturn);
	END IF;

	-- We must downgrade player one more level
	IF(isReturn=1) then
		IF (LPToDowngradeUpdLevel > newPeriodLP AND matchAnyVipLevel) THEN
			CALL PlayerUpdateVIPLevel(clientStatID, isReturn);
		END IF;
	END IF;
	
END root$$

DELIMITER ;

