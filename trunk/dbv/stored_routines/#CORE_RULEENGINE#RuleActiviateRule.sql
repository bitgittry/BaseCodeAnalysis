DROP procedure IF EXISTS `RuleActiviateRule`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleActiviateRule`(ruleId BIGINT, OUT statusCode INT)
root: BEGIN
  -- Now checking for online players and creating the rule instances for the eligable players.
  -- optimized by using player selection cache 
  -- If not found in cache calling the function 
  
  DECLARE playerSelectionID BIGINT DEFAULT 0;
  DECLARE active TINYINT(1) DEFAULT 0;
  
  SET statusCode = 0;
    
  SELECT player_selection_id, is_active, start_date, end_date, has_prerequisite, days_to_achieve  
  INTO playerSelectionID, active, @startDate, @endDate, @hasPrerequisite, @daysToAchieve
  FROM gaming_rules 
  WHERE rule_id=ruleId;

  IF (playerSelectionID=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  IF (active=1) THEN
	UPDATE gaming_rules SET is_active=0 WHERE rule_id = ruleId;
  ELSE
	IF (@endDate IS NOT NULL AND @endDate<NOW()) THEN
		SET statusCode=4;
		LEAVE root;
	END IF;
	UPDATE gaming_rules SET is_active=1 WHERE rule_id = ruleId;

    IF ((@startDate IS NULL OR @startDate<=NOW()) AND (@endDate IS NULL OR @endDate>NOW()) AND @hasPrerequisite=0) THEN 

		INSERT INTO gaming_rules_instances_counter (date_created) VALUES (NOW());
		SET @counterID=LAST_INSERT_ID();    


  
    END IF;

  END IF;
  
END$$

DELIMITER ;

