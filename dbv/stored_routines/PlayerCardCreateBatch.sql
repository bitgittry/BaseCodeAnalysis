DROP procedure IF EXISTS `PlayerCardCreateBatch`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerCardCreateBatch`(cardAmount BIGINT,batchType TINYINT(4), cardFirstNumber BIGINT, isAuto TINYINT(1), OUT statusCode INT, OUT lastInsertID BIGINT)
root: BEGIN
 -- Committing to DBV
/* Status Codes
* 0 - Success 
* 1 - Invalid Imported Batch Card FirstNumber (batch overlap)
* 2 - Invalid Card Amount (batch overlap) 
* 3 - Invalid Card Number
* 4 - Impossible to create auto batch - setting disabled
* 5 - Invalid Card Amount (negative number or 0)
*/   
	DECLARE batchOverlapCheck,  autoCreateBatch INT DEFAULT 0;
	DECLARE fromCardNumber, toCardNumber BIGINT DEFAULT 0;
    DECLARE printStatus TINYINT DEFAULT 2;
    DECLARE defaultCardAmountNumber BIGINT DEFAULT 0;
     
    SET statusCode=0;
    SET lastInsertID = 100;  
 
	SELECT MAX(IF(name = 'autocreate_batch_cards_amount', value_int,NULL)), MAX(IF(name = 'autocreate_online_batch', value_int,NULL)) INTO defaultCardAmountNumber, autoCreateBatch
		FROM gaming_playercard_settings;
	 
	IF (isAuto = 1  AND autoCreateBatch = 0) THEN
		SET statusCode=4;
		LEAVE root;
	END IF;
    
    
    IF(isAuto = 1  AND autoCreateBatch = 1) THEN 
		SET cardAmount = defaultCardAmountNumber;
    END IF;
  
	IF (cardAmount IS NULL OR cardAmount < 1)THEN
		SET statusCode=5;
		LEAVE root;
    END IF;
     
    IF(batchType = 2) THEN
     
		IF (cardFirstNumber <= 0 OR cardFirstNumber IS NULL) THEN
			SET statusCode=3;
			LEAVE root;
		END IF;
    
		-- imported batch check overlap with existing batches
		SELECT count(playercard_batch_id) INTO batchOverlapCheck FROM gaming_playercard_batches 
			WHERE (cardFirstNumber BETWEEN from_card_number AND to_card_number) 
				OR ((cardFirstNumber - 1) + cardAmount BETWEEN from_card_number AND to_card_number)
                OR ((from_card_number BETWEEN cardFirstNumber AND (cardFirstNumber + cardAmount - 1)) OR to_card_number between cardFirstNumber and (cardFirstNumber + cardAmount - 1));
    
		IF (batchOverlapCheck > 0) THEN
			SET statusCode=1;
			LEAVE root;
		END IF;
     
		SELECT  cardFirstNumber, (cardFirstNumber - 1) + cardAmount INTO fromCardNumber, toCardNumber;
    
		--  imoprted set printing status to printed
		SELECT 1 INTO printStatus;
	ELSE 
		IF (SELECT EXISTS(SELECT 1 FROM gaming_playercard_batches)) THEN
			-- get the first available card number  
			SELECT (t1.to_card_number + 1) as gap_starts,  t1.to_card_number + cardAmount as gap_ends
				INTO fromCardNumber , toCardNumber
			FROM gaming_playercard_batches t1
			WHERE NOT EXISTS (SELECT t2.to_card_number FROM gaming_playercard_batches t2 WHERE t2.from_card_number = t1.to_card_number + 1)
			ORDER  BY t1.from_card_number
					LIMIT 1;
	 
			-- check overlap with existing imported batches
			SELECT COUNT(playercard_batch_id) INTO batchOverlapCheck FROM gaming_playercard_batches 
				WHERE ((fromCardNumber) + 1 BETWEEN from_card_number AND to_card_number) 
                OR ((fromCardNumber + cardAmount - 1) BETWEEN from_card_number AND to_card_number)
				OR ((from_card_number BETWEEN fromCardNumber and (fromCardNumber +  cardAmount - 1)) OR to_card_number BETWEEN fromCardNumber AND (fromCardNumber + cardAmount - 1));
                
			IF (batchOverlapCheck > 0) THEN
				-- get number after the imported
				SELECT MAX(to_card_number) + 1, MAX(to_card_number) + cardAmount INTO fromCardNumber, toCardNumber FROM gaming_playercard_batches ORDER BY playercard_batch_id DESC LIMIT 1;        
			END IF;
		ELSE 
			-- no batches exists get value from global settings
			SELECT value_int, (value_int - 1) + cardAmount INTO  fromCardNumber, toCardNumber FROM gaming_settings WHERE name='PLAYERCARD_FIRST_CARD_BATCH_NUMBER' ;
		END IF;
	END IF;
  
	IF(fromCardNumber <= 0 OR toCardNumber <= 0)THEN
		SET statusCode=2;
		LEAVE root;
	END IF;


    INSERT INTO gaming_playercard_batches (type, from_card_number, to_card_number, cards_created, printing_status) VALUES
    (batchType, fromCardNumber, toCardNumber, cardAmount, printStatus);

  SET lastInsertID =  LAST_INSERT_ID();
    
END root$$

DELIMITER ;

