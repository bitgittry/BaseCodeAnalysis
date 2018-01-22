DROP procedure IF EXISTS `CommonWalletCheckTransactionProcessed`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletCheckTransactionProcessed`(
  transactionRef VARCHAR(80), gameManufacturerName VARCHAR(80), cwRequestType VARCHAR(80), 
  usePrevious TINYINT(1), OUT cwTransactionID BIGINT, OUT isAlreadyProcessed INT)
root: BEGIN

  -- optimized
  
  DECLARE cwRequestID BIGINT DEFAULT NULL; 
  DECLARE isSuccessful, tranSuccess, isAlreadyProcessedReturn TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayID BIGINT DEFAULT NULL;
  SET cwTransactionID = NULL; 
  
  SELECT gaming_cw_transactions.cw_transaction_id, gaming_cw_transactions.is_success, gaming_cw_transactions.game_play_id 
  INTO cwTransactionID, tranSuccess, gamePlayID
  FROM gaming_cw_transactions FORCE INDEX (transaction_ref)
  STRAIGHT_JOIN gaming_game_manufacturers FORCE INDEX (PRIMARY) ON 
	gaming_cw_transactions.transaction_ref=transactionRef AND 
    (	gaming_game_manufacturers.game_manufacturer_id=gaming_cw_transactions.game_manufacturer_id AND 
		gaming_game_manufacturers.name=gameManufacturerName AND 
	    (gaming_game_manufacturers.tran_ref_reset_date IS NULL OR gaming_cw_transactions.timestamp>=tran_ref_reset_date)) 
  LEFT JOIN gaming_cw_request_types FORCE INDEX (PRIMARY) ON
	gaming_cw_request_types.cw_request_type_id=gaming_cw_transactions.cw_request_type_id
  WHERE gaming_cw_transactions.cw_request_type_id IS NULL OR gaming_cw_request_types.name=cwRequestType
  ORDER BY gaming_cw_transactions.cw_transaction_id DESC 
  LIMIT 1;
  	
  IF (cwTransactionID IS NOT NULL) THEN    
    
    IF (tranSuccess=1) THEN 
      SET isAlreadyProcessed=1;
      
      
      IF (gamePlayID IS NOT NULL AND usePrevious=0) THEN
        CALL CommonWalletPlayReturnData(cwTransactionID);
        SET isAlreadyProcessedReturn=IF(isAlreadyProcessed,1,0); 
        SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessedReturn AS already_processed;
      
      ELSE
        CALL CommonWalletCheckTransactionReturnPrevious(transactionRef, gameManufacturerName, cwRequestType, cwTransactionID);
        SET cwTransactionID=NULL; 
      END IF;
    ELSE
      SET isAlreadyProcessed=0; 
      
    END IF;
  ELSE
    SET isAlreadyProcessed=0;
  END IF;
  
  
END root$$

DELIMITER ;

