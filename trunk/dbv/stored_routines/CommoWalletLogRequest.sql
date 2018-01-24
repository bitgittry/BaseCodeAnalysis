DROP procedure IF EXISTS `CommonWalletLogRequest`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletLogRequest`(gameManufacturerName VARCHAR(80), clientStatID BIGINT, varRequest MEDIUMTEXT, varResponse MEDIUMTEXT, transactionRef VARCHAR(80), roundRef VARCHAR(80), requestType VARCHAR(80), isSuccessful TINYINT(1), requestStatus VARCHAR(80), durationMS INT, cwTransactionIDArray VARCHAR(1024), OUT statusCode INT)
root: BEGIN
  
  
  DECLARE cwRequestID, cwTransactionID BIGINT DEFAULT -1;
  DECLARE numTries INT DEFAULT 0;
  
  
  DECLARE curPosition INT DEFAULT 1;
  DECLARE remainder TEXT;
  DECLARE delimiter, curString VARCHAR(256);
  DECLARE delimiterLength TINYINT UNSIGNED;
  
  
  SET transactionRef=IF(transactionRef='', NULL, transactionRef);
  SET roundRef=IF(roundRef='', NULL, roundRef);
  SET statusCode=0;
       
  INSERT INTO gaming_cw_requests (client_stat_id, game_manufacturer_id, request, response, timestamp, cw_request_type_id, transaction_ref, round_ref, cw_request_status_id, is_successful, num_tries, duration_ms) 
  SELECT clientStatID, gaming_game_manufacturers.game_manufacturer_id, varRequest, varResponse, NOW(), gaming_cw_request_types.cw_request_type_id, transactionRef, roundRef, gaming_cw_request_statuses.cw_request_status_id, isSuccessful, 1, durationMS 
  FROM gaming_game_manufacturers 
  JOIN gaming_cw_request_statuses ON gaming_cw_request_statuses.name=requestStatus
  LEFT JOIN gaming_cw_request_types ON gaming_cw_request_types.name=requestType AND gaming_cw_request_types.game_manufacturer_id=IFNULL(cw_request_type_ref, gaming_game_manufacturers.game_manufacturer_id)
  WHERE gaming_game_manufacturers.name=gameManufacturerName
  LIMIT 1;
  
  SET cwRequestID=LAST_INSERT_ID();
  IF (cwRequestID=-1) THEN
    SET statusCode=1;
	LEAVE root;
  END IF;
    
  IF (cwTransactionIDArray IS NOT NULL) THEN
    SET curPosition=1;
    SET delimiter=',';
    SET remainder = cwTransactionIDArray;
    SET delimiterLength = CHAR_LENGTH(delimiter);
    WHILE CHAR_LENGTH(remainder) > 0 AND curPosition > 0 DO
      SET curPosition = INSTR(remainder, delimiter);
      IF curPosition = 0 THEN
        SET curString = remainder;
      ELSE
        SET curString = LEFT(remainder, curPosition - 1);
      END IF;
      IF TRIM(curString) != '' THEN
        SET cwTransactionID=curString;    
        INSERT INTO gaming_cw_request_transactions (cw_request_id, cw_transaction_id) VALUES (cwRequestID, cwTransactionID);        
        UPDATE gaming_cw_transactions SET cw_request_id=cwRequestID WHERE cw_transaction_id=cwTransactionID;
      END IF;
      SET remainder = SUBSTRING(remainder, curPosition + delimiterLength);
    END WHILE;
  END IF;
END root$$

DELIMITER ;

