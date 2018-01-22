DROP procedure IF EXISTS `RuleUpdateRule`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleUpdateRule`(ruleId BIGINT,rule_name VARCHAR(255),friendly_name VARCHAR(255),reoccuring BIT(1),playerSelectionId BIGINT(20),
                                    has_prerequisite TINYINT(1), interval_multiplier INT,max_occurrences INT,rule_query VARCHAR(255),
                                    end_date DATETIME, start_date DATETIME, days_to_achieve INT, player_max_occurrences INT, achievement_interval_type VARCHAR(255), OUT statusCode INT)
root: BEGIN
  
  DECLARE  selectionExistsId, nameExistsId, achievmentIntervalTypeId BIGINT DEFAULT 0;
  SET statusCode=0;
    
  IF (achievement_interval_type IS NOT NULL) THEN
    SELECT query_date_interval_type_id INTO achievmentIntervalTypeId FROM gaming_query_date_interval_types WHERE name=achievement_interval_type;
    IF (achievmentIntervalTypeId=0) THEN
      SET statusCode=1;
      LEAVE root;
    END IF;
  END IF;
  
  SELECT player_selection_id INTO selectionExistsId FROM gaming_player_selections WHERE player_selection_id=playerSelectionId;
  IF (selectionExistsId=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT rule_id INTO nameExistsId FROM gaming_rules WHERE gaming_rules.name=rule_name AND rule_id!=ruleId AND is_hidden=0;
  IF (nameExistsId!=0) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  IF (end_date IS NOT NULL AND end_date<NOW()) THEN
		SET statusCode=4;
		LEAVE root;
	END IF;
  UPDATE gaming_rules SET name = rule_name,friendly_name = friendly_name, reoccuring = reoccuring,player_selection_id = playerSelectionId,
  has_prerequisite = has_prerequisite, interval_multiplier = interval_multiplier,
  max_occurrences=max_occurrences, rule_query=rule_query,end_date=end_date,start_date=start_date,days_to_achieve=days_to_achieve,player_max_occurrences=player_max_occurrences,
   achievement_interval_type_id = achievmentIntervalTypeId
  WHERE rule_id=ruleId;
END$$

DELIMITER ;

