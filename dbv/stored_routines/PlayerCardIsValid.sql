 
DROP procedure IF EXISTS `PlayerCardIsValid`;

DELIMITER $$
 
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerCardIsValid`(playerCardNumber BIGINT, OUT statusCode INT)
root: BEGIN
 
/* Status Codes
* 0 - Success 
* 1 - No free batch available to create the card
* 2 - Played Card already exists 
* 3 - Error creating an automatic batch when no free batches are available  
*/    
	DECLARE availableCards, autoCreateBatch, cardsCheck,  monthsBeforeExpiration, cardsCreated, autoissueVirtualCard INT DEFAULT 0;
    DECLARE batchId, batchConsumed BIGINT;
    DECLARE currentBalance DECIMAL(18,5);
     
    SET statusCode=0; 
     
    SELECT MAX(IF(name = 'autocreate_online_batch', value_int,NULL)), MAX(IF(name = 'months_before_expiration', value_int,NULL)), MAX(IF(name = 'autoissue_virtual_card', value_int,NULL)) 
    INTO autoCreateBatch, monthsBeforeExpiration, autoissueVirtualCard
		FROM gaming_playercard_settings;
	
    -- autocreated card - no number supplied
    IF(playerCardNumber IS NULL) THEN 
		
        IF(autoCreateBatch = 0 AND autoissueVirtualCard = 1)THEN
			SET statusCode=3;
			LEAVE root;
		END IF;
		-- check that an available online batch exists
		SELECT IFNULL(SUM(cards_created) - SUM(cards_consumed),0) INTO availableCards 
			FROM gaming_playercard_batches WHERE `type` = 0 ;
		
        IF(availableCards = 0)THEN
			SET statusCode=1;
			LEAVE root;
        END IF;  
        
	ELSE
 
		 -- check that an available retail batch exists
		SELECT IFNULL(SUM(cards_created) - SUM(cards_consumed), 0) INTO availableCards FROM gaming_playercard_batches 
			WHERE (`type` = 1 OR `type` = 2) AND (printing_status = 2 OR printing_status = 1);
		IF(availableCards = 0)THEN
			-- error no space available on batches
			SET statusCode=1;
			LEAVE root;
		END IF;
		 
		-- check player card number not exists already
		SELECT COUNT(*) INTO cardsCheck FROM gaming_playercard_cards 
			WHERE playercard_cards_id = playerCardNumber ;
		IF(cardsCheck > 0)THEN
			SET statusCode=2;
			LEAVE root;
		END IF;
	
		-- get related batch
		SELECT playercard_batch_id, cards_consumed, cards_created INTO batchId, batchConsumed, cardsCreated  FROM gaming_playercard_batches 
			WHERE playerCardNumber  BETWEEN from_card_number AND to_card_number;
 
		IF(batchId IS NULL) THEN
			SET statusCode=3;
			LEAVE root;
		END IF;
    END IF;     
    
END root$$

DELIMITER ;

