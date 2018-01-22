DROP procedure IF EXISTS `RulesQueueAwards`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RulesQueueAwards`(input TEXT, varDelimiter VARCHAR(10))
BEGIN
	DECLARE curPosition INT DEFAULT 1 ;    
  DECLARE remainder TEXT;   
  DECLARE curString VARCHAR(256);    
  DECLARE arrayCounterID BIGINT DEFAULT -1;    
  DECLARE delimiterLength TINYINT UNSIGNED;     
     
  SET arrayCounterID=LAST_INSERT_ID();    
  SET remainder = input;    
  SET delimiterLength = CHAR_LENGTH(varDelimiter);     
  WHILE CHAR_LENGTH(remainder) > 0 AND curPosition > 0 DO        
    SET curPosition = INSTR(remainder, varDelimiter);        
    IF curPosition = 0 THEN            
      SET curString = remainder;        
      ELSE            
      SET curString = LEFT(remainder, curPosition - 1);       
    END IF;       
    IF TRIM(curString) != '' THEN          
      INSERT INTO gaming_rules_to_award (rule_instance_id) 
      VALUES (curString);      
    END IF;     
    SET remainder = SUBSTRING(remainder, curPosition + delimiterLength);  
  END WHILE; 
END$$

DELIMITER ;

