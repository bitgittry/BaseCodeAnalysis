DROP procedure IF EXISTS `CommonWalletGeneralCheckTransactionProcessed`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGeneralCheckTransactionProcessed`(
  transactionRef VARCHAR(80), gameManufacturerName VARCHAR(80), transactionType VARCHAR(80),
  OUT cwTransactionID BIGINT, OUT isAlreadyProcessed INT, INOUT prevStatusCode INT)
root: BEGIN
  
  -- optimized
  
  DECLARE cwRequestID BIGINT DEFAULT NULL; 
  DECLARE isSuccessful, tranSuccess, isAlreadyProcessedReturn TINYINT(1) DEFAULT 0; 
  DECLARE gamePlayID BIGINT DEFAULT NULL;
  SET cwTransactionID = NULL; 
  
  SELECT gaming_cw_transactions.cw_transaction_id, gaming_cw_transactions.is_success, gaming_cw_transactions.game_play_id, gaming_cw_transactions.status_code 
  INTO cwTransactionID, tranSuccess, gamePlayID, prevStatusCode
  FROM gaming_cw_transactions FORCE INDEX (transaction_ref)
  STRAIGHT_JOIN gaming_game_manufacturers FORCE INDEX (PRIMARY) ON 
	gaming_cw_transactions.transaction_ref=transactionRef AND 
    (	gaming_game_manufacturers.game_manufacturer_id=gaming_cw_transactions.game_manufacturer_id AND 
		gaming_game_manufacturers.name=gameManufacturerName AND 
	    (gaming_game_manufacturers.tran_ref_reset_date IS NULL OR gaming_cw_transactions.timestamp>=tran_ref_reset_date)) 
  LEFT JOIN gaming_payment_transaction_type ON  
	gaming_payment_transaction_type.payment_transaction_type_id=gaming_cw_transactions.payment_transaction_type_id
  WHERE transactionType IS NULL OR gaming_payment_transaction_type.name=transactionType  
  ORDER BY gaming_cw_transactions.cw_transaction_id DESC 
  LIMIT 1;
  
  IF (cwTransactionID IS NOT NULL) THEN    
    
    IF (tranSuccess=1) THEN 
      
      
      IF (gamePlayID IS NOT NULL) THEN
        CALL CommonWalletPlayReturnData(cwTransactionID);
      ELSE
        SET prevStatusCode=IFNULL(prevStatusCode, -1); 
      END IF;
      
      SET isAlreadyProcessed=1;
      SET isAlreadyProcessedReturn=IF(isAlreadyProcessed,1,0); 
      SELECT cwTransactionID AS cw_transaction_id, isAlreadyProcessedReturn AS already_processed;
    ELSE
      SET isAlreadyProcessed=0; 
      
    END IF;
  ELSE
    SET isAlreadyProcessed=0;
  END IF;
  
END root$$

DELIMITER ;

