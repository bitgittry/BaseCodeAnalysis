DROP procedure IF EXISTS `PlayerCardUpdateBatch`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerCardUpdateBatch`(batchId BIGINT, cardAmount INT, printStatus TINYINT(4), OUT statusCode INT)
root: BEGIN
 -- Committing to DBV
/* Status Codes
* 0 - Success 
* 1 - Batch has already one or more cards created
* 2 - Invalid Card Amount (batch overlap) 
*/ 
	DECLARE cardsConsumed, batchOverlapCheck INT DEFAULT 0;
	DECLARE fromCardNumber BIGINT(20) DEFAULT 0;
	DECLARE printCurrentStatus TINYINT(4) DEFAULT 0;
	SET statusCode=0;
     
    -- check no cards are consumed
	SELECT cards_consumed, from_card_number, printing_status INTO cardsConsumed, fromCardNumber, printCurrentStatus 
		FROM gaming_playercard_batches where playercard_batch_id = batchId;
    
	IF (cardsConsumed > 0) THEN
		SET statusCode=1;
		LEAVE root; 
	END IF;
    -- if print status is not passed it gets the previous value
	IF (printStatus IS NULL) THEN
		SET printStatus=printCurrentStatus;
	END IF;
 
	-- check overlap with other existing batches
	SELECT count(playercard_batch_id) INTO batchOverlapCheck FROM gaming_playercard_batches
		WHERE batchId <>  playercard_batch_id AND  (((fromCardNumber - 1) + cardAmount BETWEEN from_card_number AND to_card_number) 
        OR (from_card_number BETWEEN fromCardNumber AND (fromCardNumber +  cardAmount - 1)) OR to_card_number BETWEEN fromCardNumber AND (fromCardNumber + cardAmount - 1));
  
	IF (batchOverlapCheck > 0) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;        

	UPDATE gaming_playercard_batches SET to_card_number = (fromCardNumber - 1) + cardAmount, cards_created = cardAmount, printing_status = printStatus
		WHERE playercard_batch_id = batchId;
      
END root$$

DELIMITER ;

