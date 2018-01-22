DROP procedure IF EXISTS `BonusRegisterClientOptInBonuses`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusRegisterClientOptInBonuses`(clientStatID BIGINT, sessionID BIGINT, bonusRuleArray TEXT, OUT statusCode INT)
root: BEGIN
  

  DECLARE arrayCounterID, bonusRegistrationID BIGINT DEFAULT -1;
  DECLARE bonusRuleID, playerSelectionID, clientID, bonusCouponID BIGINT DEFAULT -1;
  DECLARE registrationTagName VARCHAR(255);
  DECLARE delim VARCHAR(10);
  
  SELECT gaming_clients.client_id, gaming_clients.bonus_coupon_id INTO clientID, bonusCouponID 
  FROM gaming_client_stats JOIN gaming_clients ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.client_id=gaming_clients.client_id;
  
  IF (bonusCouponID=-1) THEN
    SET statusCode=1;
  END IF;
  
  
  SELECT bonus_registration_id INTO bonusRegistrationID FROM gaming_bonus_registrations WHERE client_stat_id=clientStatID;
  
  
  IF (bonusRegistrationID=-1) THEN
    INSERT INTO gaming_bonus_registrations (client_id, client_stat_id, date_opted_in, session_id)
    SELECT client_id, clientStatID, NOW(), sessionID
    FROM gaming_client_stats WHERE client_stat_id=clientStatID;
    
    SET bonusRegistrationID=LAST_INSERT_ID();
  END IF;
  
  IF (bonusRuleArray='Registration') THEN
    INSERT INTO gaming_array_counter (date_created) VALUES (NOW());
    SET arrayCounterID=LAST_INSERT_ID();
    
    INSERT INTO gaming_array_counter_elems (array_counter_id, elem_id)
    SELECT arrayCounterID, gaming_bonus_coupons_bonus_rules.bonus_rule_id
    FROM gaming_bonus_coupons
    JOIN gaming_bonus_coupons_bonus_rules ON 
      gaming_bonus_coupons.bonus_coupon_id=bonusCouponID AND 
      gaming_bonus_coupons.bonus_coupon_id=gaming_bonus_coupons_bonus_rules.bonus_coupon_id;   
  ELSE
    SET delim=',';
    
    SET arrayCounterID=(SELECT ArrayInsertIDArray(bonusRuleArray, delim));     
  END IF;
  
  
  INSERT INTO gaming_bonus_registrations_bonus_rules (bonus_registration_id, bonus_rule_id, session_id)
  SELECT bonusRegistrationID, gaming_bonus_rules.bonus_rule_id, sessionID
  FROM gaming_array_counter_elems AS counter_elems
  JOIN gaming_bonus_rules ON counter_elems.array_counter_id=arrayCounterID AND counter_elems.elem_id=gaming_bonus_rules.bonus_rule_id
  ON DUPLICATE KEY UPDATE bonus_rule_id=gaming_bonus_rules.bonus_rule_id;
 
  
  INSERT INTO gaming_player_selections_selected_players (player_selection_id, client_stat_id, include_flag, exclude_flag) 
  SELECT player_selection_id, clientStatID, 1, 0 
  FROM gaming_array_counter_elems AS counter_elems
  JOIN gaming_bonus_rules ON counter_elems.array_counter_id=arrayCounterID AND counter_elems.elem_id=gaming_bonus_rules.bonus_rule_id
  ON DUPLICATE KEY UPDATE client_stat_id=clientStatID;
  
  
  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date)
  SELECT gaming_bonus_rules.player_selection_id, clientStatID, 1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_bonus_rules.player_selection_id)  MINUTE)
  FROM gaming_array_counter_elems AS counter_elems
  JOIN gaming_bonus_rules ON counter_elems.array_counter_id=arrayCounterID AND counter_elems.elem_id=gaming_bonus_rules.bonus_rule_id
  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
						  gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
						  gaming_player_selections_player_cache.last_updated=NOW();
  
  
  UPDATE gaming_array_counter_elems AS counter_elems
  JOIN gaming_bonus_rules ON counter_elems.array_counter_id=arrayCounterID AND counter_elems.elem_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_player_selections ON gaming_bonus_rules.player_selection_id=gaming_player_selections.player_selection_id
  SET gaming_player_selections.selected_players=1
  WHERE gaming_player_selections.selected_players=0;
  
  
  DELETE FROM gaming_array_counter_elems 
  WHERE array_counter_id=arrayCounterID;
  
  IF (sessionID > 0) THEN
    CALL BonusCheckAwardingOnLogin(sessionID, clientStatID, null);  
  END IF;
  SET statusCode=0;  
END root$$

DELIMITER ;

