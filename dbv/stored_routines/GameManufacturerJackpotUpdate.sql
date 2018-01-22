DROP procedure IF EXISTS `GameManufacturerJackpotUpdate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameManufacturerJackpotUpdate`(externalName VARCHAR(255), externalDescription VARCHAR(255), currencyID BIGINT, currentValue DECIMAL(18, 5), gameManufacturerID BIGINT, gameNames TEXT, ignoreInactive tinyint(1))
BEGIN
  DECLARE varDelimiter VARCHAR(10);
  DECLARE curPosition INT DEFAULT 1;
  DECLARE remainder TEXT;
  DECLARE curString VARCHAR(256);
  DECLARE delimiterLength TINYINT UNSIGNED;
  DECLARE currentDate DATETIME;
  DECLARE gameManufacturerJackpotID BIGINT DEFAULT -1;
  DECLARE updateGameList TINYINT(1) DEFAULT 0;
  
  SET currentDate=NOW();
  
  SELECT game_manufacturer_jackpot_id, update_game_list INTO gameManufacturerJackpotID, updateGameList
  FROM gaming_game_manufacturers_jackpots 
  WHERE external_name=externalName AND (is_active=1 OR ignoreInactive = 1);
  
  IF (gameManufacturerJackpotID=-1) THEN
    INSERT INTO gaming_game_manufacturers_jackpots (name, display_name, external_name, currency_id, current_value, game_manufacturer_id, update_game_list, is_active, date_created, last_updated)
    VALUES (externalDescription, externalDescription, externalName, currencyID, currentValue, gameManufacturerID, 0, 1, currentDate, currentDate);
    
    SET gameManufacturerJackpotID=LAST_INSERT_ID();
    SET updateGameList=1;
  ELSE
    UPDATE gaming_game_manufacturers_jackpots
    SET currency_id=currencyID, current_value=currentValue, last_updated=currentDate, update_game_list=0
    WHERE game_manufacturer_jackpot_id=gameManufacturerJackpotID;
  END IF;
  IF (updateGameList=1) THEN
    
    DELETE FROM gaming_game_manufacturers_jackpots_games 
    WHERE game_manufacturer_jackpot_id=gameManufacturerJackpotID;
  
    
    SET varDelimiter = ',';
    SET remainder = gameNames;
    SET delimiterLength = CHAR_LENGTH(varDelimiter);
 
    WHILE CHAR_LENGTH(remainder) > 0 AND curPosition > 0 DO
      SET curPosition = INSTR(remainder, varDelimiter);
      IF curPosition = 0 THEN
          SET curString = remainder;
      ELSE
          SET curString = LEFT(remainder, curPosition - 1);
      END IF;
      IF TRIM(curString) != '' THEN
         
        INSERT INTO gaming_game_manufacturers_jackpots_games (game_manufacturer_jackpot_id, game_id, date_created)
        SELECT gameManufacturerJackpotID, IF(is_sub_game=1, parent_game_id, game_id), currentDate
        FROM gaming_games
        WHERE game_manufacturer_id=gameManufacturerID AND (manufacturer_game_idf=curString OR manufacturer_game_description=curString);
          
      END IF;
      SET remainder = SUBSTRING(remainder, curPosition + delimiterLength);
    END WHILE;    
  
  END IF;
  
END$$

DELIMITER ;

