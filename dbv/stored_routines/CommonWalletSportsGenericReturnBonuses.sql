DROP procedure IF EXISTS `CommonWalletSportsGenericReturnBonuses`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericReturnBonuses`(
  sbBetID BIGINT, maxGamePlaySBID BIGINT, cancelGamePlayID BIGINT, INOUT cancelledTotalNow DECIMAL(18,5), 
  INOUT cancelledRealNow DECIMAL(18,5), INOUT cancelledBonusNow DECIMAL(18,5), INOUT cancelledBonusWinLockedNow DECIMAL(18,5))
BEGIN

  -- :) First Version
  
  DECLARE partitioningMinusFromMax INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
    minGamePlaySBID, 
    minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL; 
  
  -- Check the bet exists and it is in the correct status
  SELECT
    gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
    gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
    gsbpf.min_game_play_sb_id, IFNULL(maxGamePlaySBID, gsbpf.max_game_play_sb_id)
  INTO minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
    minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID
  FROM gaming_sb_bets AS gsb
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
  WHERE gsb.sb_bet_id=sbBetID;

  SET @bonusTransferred=0;
  SET @bonusWinLockedTransferred=0;
  SET @bonusLost=0;
  SET @bonusWinLockedLost=0;
  SET @numBonuses=0;
  
  SELECT IFNULL(COUNT(*),0)
  INTO @numBonuses
  FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
  STRAIGHT_JOIN gaming_game_plays_sb AS bet_play_sb FORCE INDEX (game_round_id) ON 
	(bet_play_sb.game_round_id=gaming_game_plays_sb.game_round_id AND bet_play_sb.payment_transaction_type_id=12) AND
    -- parition filtering
	(bet_play_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
  STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS bet_sb_bonuses FORCE INDEX (PRIMARY) ON 
	bet_sb_bonuses.game_play_sb_id=bet_play_sb.game_play_sb_id
  WHERE gaming_game_plays_sb.game_play_id=cancelGamePlayID AND
	-- parition filtering
	(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);
  
  IF (cancelledBonusNow+cancelledBonusWinLockedNow > 0 OR @numBonuses>0) THEN
  
	  -- counter transactions for play sports bonuses
	  INSERT INTO gaming_game_plays_sb_bonuses 
		(game_play_sb_id, bonus_instance_id, bet_bonus_win_locked, bet_real, bet_bonus, wager_requirement_non_weighted,
		 wager_requirement_contribution_before_real_only, wager_requirement_contribution, wager_requirement_contribution_cancelled)
	  SELECT GREATEST(gaming_game_plays_sb.game_play_sb_id, (@adjustmentRatio:=(gaming_game_plays_sb.amount_total/bet_play_sb.amount_total*-1))), 
        bet_sb_bonuses.bonus_instance_id, bet_sb_bonuses.bet_bonus_win_locked*@adjustmentRatio, 
        bet_sb_bonuses.bet_real*@adjustmentRatio, bet_sb_bonuses.bet_bonus*@adjustmentRatio, 
		bet_sb_bonuses.wager_requirement_non_weighted*@adjustmentRatio, bet_sb_bonuses.wager_requirement_contribution_before_real_only*@adjustmentRatio, 
        bet_sb_bonuses.wager_requirement_contribution*@adjustmentRatio, bet_sb_bonuses.wager_requirement_contribution_cancelled*@adjustmentRatio
	  FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
	  STRAIGHT_JOIN gaming_game_plays_sb AS bet_play_sb FORCE INDEX (game_round_id) ON 
		bet_play_sb.game_round_id=gaming_game_plays_sb.game_round_id AND bet_play_sb.payment_transaction_type_id=12 AND
		-- parition filtering
		(bet_play_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
	  STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS bet_sb_bonuses FORCE INDEX (PRIMARY) ON 
		bet_sb_bonuses.game_play_sb_id=bet_play_sb.game_play_sb_id
	  WHERE gaming_game_plays_sb.game_play_id=cancelGamePlayID AND
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);
      
      SET @isBonusSecured=0;
	  -- Give the bonus credits back to the player
	  UPDATE 
	  (
		  SELECT cancel_sb_bonuses.bonus_instance_id, COUNT(bet_play_sb.amount_total=gaming_game_plays_sb.amount_total) AS num_rounds, 
			SUM(ABS(cancel_sb_bonuses.bet_real)) AS amount_real, 
			SUM(ABS(cancel_sb_bonuses.bet_bonus)) AS amount_bonus, 
            SUM(ABS(cancel_sb_bonuses.bet_bonus_win_locked)) AS amount_bonus_win_locked
		  FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
		  STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS cancel_sb_bonuses ON 
			gaming_game_plays_sb.game_play_sb_id=cancel_sb_bonuses.game_play_sb_id
          STRAIGHT_JOIN gaming_bonus_instances ON 
			cancel_sb_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
          STRAIGHT_JOIN gaming_game_plays_sb AS bet_play_sb FORCE INDEX (game_round_id) ON 
			bet_play_sb.game_round_id=gaming_game_plays_sb.game_round_id AND bet_play_sb.payment_transaction_type_id=12 AND
            -- parition filtering
			(bet_play_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
		  WHERE gaming_game_plays_sb.game_play_id=cancelGamePlayID AND
			-- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
		  GROUP BY cancel_sb_bonuses.bonus_instance_id
	  ) AS CancelBonus 
      STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id=CancelBonus.bonus_instance_id
	  SET gbi.bonus_amount_remaining = bonus_amount_remaining + IF(gbi.is_lost=1 OR gbi.is_secured=1, 0, CancelBonus.amount_bonus),
		  gbi.current_win_locked_amount = gbi.current_win_locked_amount + IF(gbi.is_lost=1 OR gbi.is_secured=1, 0, CancelBonus.amount_bonus_win_locked),
		  gbi.reserved_bonus_funds = gbi.reserved_bonus_funds - (CancelBonus.amount_bonus + CancelBonus.amount_bonus_win_locked),
          gbi.open_rounds  = gbi.open_rounds - CancelBonus.num_rounds,
          gbi.is_active = IF(gbi.is_secured OR gbi.is_lost=1, gbi.is_active, 1),
          gbi.is_used_all = IF((bonus_amount_remaining + CancelBonus.amount_bonus + gbi.current_win_locked_amount + CancelBonus.amount_bonus_win_locked) = 0
			AND (gbi.open_rounds - CancelBonus.num_rounds) = 0, 1, gbi.is_used_all);
      
      -- If it is secured need to give the player the bonus to real
	  SELECT 
		IFNULL(SUM(ABS(cancel_sb_bonuses.bet_bonus)),0) AS amount_bonus, 
        IFNULL(SUM(ABS(cancel_sb_bonuses.bet_bonus_win_locked)),0) AS amount_bonus_win_locked
	  INTO @bonusTransferred, @bonusWinLockedTransferred
	  FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
	  STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS cancel_sb_bonuses ON 
		gaming_game_plays_sb.game_play_sb_id=cancel_sb_bonuses.game_play_sb_id
	  STRAIGHT_JOIN gaming_bonus_instances ON 
		cancel_sb_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND gaming_bonus_instances.is_secured=1
	  WHERE gaming_game_plays_sb.game_play_id=cancelGamePlayID AND
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);
 
		IF ((@bonusTransferred + @bonusWinLockedTransferred) > 0) THEN
            SET cancelledRealNow=cancelledRealNow + @bonusTransferred + @bonusWinLockedTransferred;
            SET cancelledBonusNow=cancelledBonusNow-@bonusTransferred;
            SET cancelledBonusWinLockedNow=cancelledBonusWinLockedNow-@bonusWinLockedTransferred;
            
            SET cancelledTotalNow=cancelledRealNow+cancelledBonusNow+cancelledBonusWinLockedNow;
		END IF;

	  SELECT 
		IFNULL(SUM(ABS(cancel_sb_bonuses.bet_bonus)),0) AS amount_bonus, 
		IFNULL(SUM(ABS(cancel_sb_bonuses.bet_bonus_win_locked)),0) AS amount_bonus_win_locked
	  INTO @bonusLost, @bonusWinLockedLost
	  FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
	  STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS cancel_sb_bonuses ON 
		gaming_game_plays_sb.game_play_sb_id=cancel_sb_bonuses.game_play_sb_id
	  STRAIGHT_JOIN gaming_bonus_instances ON 
		cancel_sb_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND gaming_bonus_instances.is_lost=1
	  WHERE gaming_game_plays_sb.game_play_id=cancelGamePlayID AND
		-- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);
		  
          IF ((@bonusLost + @bonusWinLockedLost) > 0) THEN
            SET cancelledBonusNow=cancelledBonusNow-@bonusLost;
            SET cancelledBonusWinLockedNow=cancelledBonusWinLockedNow-@bonusWinLockedLost;
            
            SET cancelledTotalNow=cancelledRealNow+cancelledBonusNow+cancelledBonusWinLockedNow;
		END IF;
        
  END IF;

END$$

DELIMITER ;

