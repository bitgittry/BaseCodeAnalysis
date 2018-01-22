DROP procedure IF EXISTS `RuleInsertNewRule`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertNewRule`(rule_name VARCHAR(255),friendly_name VARCHAR(255),reoccuring BIT(1),playerSelectionId BIGINT(20),
                                    has_prerequisite TINYINT(1),interval_multiplier INT,max_occurrences INT,
                                    rule_query VARCHAR(255),end_date DATETIME, start_date DATETIME, days_to_achieve INT,player_max_occurrences INT, is_vip_rule TINYINT(1), achievement_interval_type VARCHAR(255), OUT statusCode INT, OUT ruleId BIGINT(20))
root: BEGIN
  
  DECLARE selectionExistsId BIGINT DEFAULT 0;
  DECLARE nameExistsId BIGINT DEFAULT 0;
  DECLARE intervalTypeIdAchievment BIGINT DEFAULT 0;
  SET statusCode=0;
  
  IF (achievement_interval_type IS NOT NULL) THEN
    SELECT query_date_interval_type_id INTO intervalTypeIdAchievment FROM gaming_query_date_interval_types WHERE name=achievement_interval_type;
    IF (intervalTypeIdAchievment=0) THEN
      SET statusCode=1; 
      LEAVE root;
    END IF;
  END IF;
  
  SELECT player_selection_id INTO selectionExistsId FROM gaming_player_selections WHERE player_selection_id=playerSelectionId;
  IF (selectionExistsId=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
 SELECT rule_id INTO nameExistsId FROM gaming_rules WHERE gaming_rules.name=rule_name AND is_hidden=0;
  IF (nameExistsId!=0) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  IF (end_date IS NOT NULL AND end_date<NOW()) THEN
		SET statusCode=4;
		LEAVE root;
	END IF;


  INSERT INTO gaming_rules (name,friendly_name,reoccuring,player_selection_id,has_prerequisite, interval_multiplier,max_occurrences,rule_query,end_date,start_date,days_to_achieve,player_max_occurrences,is_vip_rule, achievement_interval_type_id) 
  VALUES (rule_name,friendly_name,reoccuring,playerSelectionId,has_prerequisite,interval_multiplier,max_occurrences,rule_query,end_date,start_date,IF(days_to_achieve=0,NULL,days_to_achieve),player_max_occurrences,is_vip_rule, intervalTypeIdAchievment);
  
  SET ruleId = LAST_INSERT_ID();
  
END$$

DELIMITER ;

