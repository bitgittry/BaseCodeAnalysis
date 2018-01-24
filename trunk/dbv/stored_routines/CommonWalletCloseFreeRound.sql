DROP procedure IF EXISTS `CommonWalletCloseFreeRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCloseFreeRound`(roundRef BIGINT, gameManufacturerID BIGINT, clientStatID BIGINT)
root:BEGIN

  -- Added return of gameRoundID

  DECLARE gameRoundID, operatorGameID BIGINT DEFAULT -1;
  DECLARE isOpen TINYINT(1) DEFAULT 0;
  DECLARE sessionID, bonusInstanceID BIGINT DEFAULT -1;
  DECLARE awardingType, gameManufacturerName VARCHAR(80) DEFAULT NULL;
  DECLARE numFreeRoundsUsed INT DEFAULT 1;
  DECLARE cwFreeRoundID BIGINT DEFAULT -1;
  DECLARE FreeRoundsRemaining INT DEFAULT -1;

  SELECT game_round_id, NOT gaming_game_rounds.is_round_finished, operator_game_id, ggm.name
  INTO gameRoundID, isOpen, operatorGameID, gameManufacturerName
  FROM gaming_game_rounds
  JOIN gaming_game_manufacturers ggm ON ggm.game_manufacturer_id = gaming_game_rounds.game_manufacturer_id
  WHERE gaming_game_rounds.round_ref=roundRef AND gaming_game_rounds.client_stat_id=clientStatID AND gaming_game_rounds.game_manufacturer_id=gameManufacturerID
  ORDER BY game_round_id DESC LIMIT 1;
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
   
  IF (isOpen AND gameRoundID!=-1) THEN
    
    UPDATE gaming_game_rounds SET date_time_end=NOW(), is_round_finished=1, is_cancelled=(num_bets=0), is_processed=IF(num_bets=0, 1, is_processed) 
    WHERE game_round_id=gameRoundID; 
     
    UPDATE gaming_bonus_instances 
    JOIN
    (
      SELECT play_bonuses.bonus_instance_id, COUNT(*) AS num_found FROM gaming_game_plays 
      JOIN gaming_game_plays_bonus_instances AS play_bonuses ON gaming_game_plays.game_round_id=gameRoundID AND
        gaming_game_plays.game_play_id=play_bonuses.game_play_id
      GROUP BY play_bonuses.bonus_instance_id
    ) AS BB ON gaming_bonus_instances.bonus_instance_id=BB.bonus_instance_id
    SET open_rounds=open_rounds-1;

	SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_types_awarding.name, gaming_game_sessions.session_id, gaming_cw_free_rounds.cw_free_round_id, gaming_cw_free_rounds.free_rounds_remaining
	INTO bonusInstanceID, awardingType, sessionID, cwFreeRoundID, FreeRoundsRemaining
    FROM gaming_bonus_instances
    JOIN gaming_cw_free_rounds ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id 
    JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.cw_free_round_status_id = gaming_cw_free_rounds.cw_free_round_status_id
    JOIN gaming_game_rounds ON gaming_game_rounds.round_ref = roundRef AND gaming_game_rounds.game_manufacturer_id = gameManufacturerID
    JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_cw_free_rounds.bonus_rule_id
    JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
    JOIN gaming_game_sessions ON gaming_game_sessions.client_stat_id = clientStatID AND gaming_game_sessions.game_id = gaming_cw_free_rounds.game_id_awarded AND cw_game_latest = 1
    WHERE gaming_cw_free_rounds.client_stat_id = clientStatID 
          AND gaming_cw_free_round_statuses.name = 'StartedBeingUsed' 
    	  AND gaming_cw_free_rounds.game_id_awarded = gaming_game_rounds.game_id
    ORDER BY gaming_bonus_instances.cw_free_round_id DESC LIMIT 1;

	IF(gameManufacturerName='Microgaming' OR numFreeRoundsUsed != FreeRoundsRemaining) THEN
    # By default Microgaming send end game request /closing round/ when all free spins are exhausted
    # We do this correction because bonus instance could not be synchronized with Microgaming free round profiles from MG side.
    SET numFreeRoundsUsed = FreeRoundsRemaining;
    END IF;
    
	UPDATE gaming_cw_free_rounds
	SET free_rounds_remaining = free_rounds_remaining - numFreeRoundsUsed
	WHERE cw_free_round_id = cwFreeRoundID;

	IF (FreeRoundsRemaining = numFreeRoundsUsed) THEN 
		# Round is closed and no more free spins exist
		CALL BonusFreeRoundsOnRedeemUpdateStats(bonusInstanceID, 0);
	
		IF (awardingType = 'CashBonus') THEN
			CALL BonusRedeemAllBonus(bonusInstanceID, sessionID, -1, 'CashBonus', 'CashBonus', -1);
		END IF;
	END IF;
  END IF;
  
  CALL PlayReturnPlayBalanceData(clientStatID, operatorGameID);
  SELECT gameRoundID AS game_round_id;
  
END root$$

DELIMITER ;

