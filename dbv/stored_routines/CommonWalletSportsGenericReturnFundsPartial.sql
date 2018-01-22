DROP procedure IF EXISTS `CommonWalletSportsGenericReturnFundsPartial`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericReturnFundsPartial`(
  singleID BIGINT, multipleID BIGINT, returnData TINYINT(1), backOfficeRequest TINYINT (1), OUT statusCode INT)
root: BEGIN
	
    DECLARE sbBetID BIGINT DEFAULT -1;
    DECLARE playWagerType VARCHAR(80) DEFAULT 'Type1';
    
	SELECT gs1.value_string as vs1
	INTO playWagerType
	FROM gaming_settings gs1
	WHERE gs1.name = 'PLAY_WAGER_TYPE';
    
    SET statusCode = -1;
    
	IF (singleID) THEN
		UPDATE gaming_sb_bet_singles FORCE INDEX (PRIMARY) 
		SET processing_status = 1 
		WHERE sb_bet_single_id = singleID AND processing_status = 0;
        
        SELECT sb_bet_id INTO sbBetID FROM gaming_sb_bet_singles WHERE sb_bet_single_id = singleID;
	END IF;
    
    IF (multipleID) THEN
		UPDATE gaming_sb_bet_multiples FORCE INDEX (PRIMARY) 
		SET processing_status = 1 
		WHERE sb_bet_multiple_id = multipleID AND processing_status = 0;
	
		SELECT sb_bet_id INTO sbBetID FROM gaming_sb_bet_multiples 
		WHERE sb_bet_multiple_id = multipleID;
    END IF;
    
    IF(sbBetID > 0) THEN 
    	IF (playWagerType = 'Type1') THEN
			CALL CommonWalletSportsGenericReturnFunds(sbBetID, returnData, backOfficeRequest, 0, statusCode);
		ELSE
			CALL CommonWalletSportsGenericReturnFundsTypeTwo(sbBetID, returnData, backOfficeRequest, 0, statusCode);
		END IF;
    END IF;

END root$$

DELIMITER ;

