DROP procedure IF EXISTS `PlayerCardCreateCard`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerCardCreateCard`(playerCardNumber BIGINT, sessionID BIGINT,  playerId BIGINT, expirationDate DATETIME, fee DECIMAL(18,5), printStatus TINYINT(4),  OUT statusCode INT, OUT lastInsertID BIGINT)
root: BEGIN

	DECLARE autoCreateBatch, cardsCheck, monthsBeforeExpiration, transactionStatusCode INT DEFAULT 0;
	DECLARE availableCards,fromCard, toCard, cardsCreated, batchConsumed BIGINT DEFAULT 0;
    DECLARE defaultCardAmountNumber, batchId, clientStatId BIGINT DEFAULT NULL;
    DECLARE currentBalance DECIMAL(18,5);
    DECLARE expirationUnlimited, batchPrintStatus TINYINT(1) DEFAULT 0;
	DECLARE nowDateTime DATE DEFAULT NOW();
  
    SET statusCode=0; 
    SET lastInsertID =0;
     
    SELECT 
		MAX(IF(name = 'autocreate_online_batch', value_int,NULL)),  
		MAX(IF(name = 'months_before_expiration', value_int,NULL)) 
	INTO autoCreateBatch, monthsBeforeExpiration
	FROM gaming_playercard_settings;
	  
	-- Check how many active cards the player have
    SELECT COUNT(*) INTO cardsCheck FROM gaming_playercard_cards 
	WHERE client_id = playerId AND card_status = 0;
	
    -- cannot have more then 1 active card
    IF(cardsCheck > 0)THEN
		SET statusCode=4;
		LEAVE root;
	END IF; 
       
	-- If card number is not supplied
    IF(playerCardNumber IS NULL) THEN 
         
        IF(printStatus IS NULL OR (printStatus != 0 AND printStatus != 2)) THEN
         	SET statusCode=7;
			LEAVE root;
		END IF;
        
        -- Check if batch can issue more cards
		SELECT IFNULL(SUM(cards_created) - SUM(cards_consumed),0) 
        INTO availableCards 
		FROM gaming_playercard_batches WHERE `type` = 0 ;
		
        IF (availableCards = 0) THEN
			
            -- Create new batch on the fly
			IF(autoCreateBatch = 1 AND playerCardNumber IS NULL)THEN
				SET @returnCode = -1;  
				CALL PlayerCardCreateBatch(NULL, 0, NULL, 1, @returnCode, @returnData);
				IF(@returnCode <> 0)THEN
					SET statusCode=3;
					
					CALL NotificationEventCreate(611, -1, playerId, 0);
					LEAVE root;
				END IF;
			ELSE
				SET statusCode=1;
                
				CALL NotificationEventCreate(611, -1, playerId, 0);
				LEAVE root;
            END IF;
        END IF;
	 
		-- get batch details
        SELECT from_card_number, to_card_number 
        INTO fromCard, toCard 
        FROM gaming_playercard_batches  
		WHERE type = 0  AND cards_consumed < cards_created 
        ORDER BY playercard_batch_id LIMIT 1;
   
		-- 
        SELECT IFNULL(MAX(playercard_cards_id) + 1, fromCard) 
        INTO playerCardNumber 
        FROM gaming_playercard_cards 
		WHERE playercard_cards_id >= fromCard AND playercard_cards_id < toCard;
 
		SELECT playercard_batch_id, cards_consumed, cards_created 
        INTO batchId, batchConsumed, cardsCreated  
        FROM gaming_playercard_batches 
		WHERE playerCardNumber 
        BETWEEN from_card_number AND to_card_number;
 
		IF(batchId IS NULL) THEN
			SET statusCode=8;
			LEAVE root;
		END IF;
    ELSE
    
		SELECT playercard_batch_id INTO batchId 
        FROM gaming_playercard_batches 
		WHERE (`type` = 0) AND playerCardNumber BETWEEN from_card_number AND to_card_number;
            
		IF(batchId IS NOT NULL) THEN
			SET statusCode=10;
			LEAVE root;
		END IF; 
         
		SELECT IFNULL(SUM(cards_created) - SUM(cards_consumed), 0) 
        INTO availableCards 
        FROM gaming_playercard_batches 
		WHERE (`type` = 1 OR `type` = 2) AND (printing_status = 2 OR printing_status = 1);
		
        IF(availableCards = 0)THEN
			SET statusCode=1;
            
            CALL NotificationEventCreate(611, -1, playerId, 0);
			LEAVE root;
        END IF;
		  
        SELECT COUNT(*) INTO cardsCheck 
        FROM gaming_playercard_cards 
		WHERE playercard_cards_id = playerCardNumber ;
        
        IF(cardsCheck > 0)THEN
			SET statusCode=2;
			LEAVE root;
		END IF;
	     
        SET printStatus = 1;
       	
        SELECT playercard_batch_id, cards_consumed, cards_created, printing_status  
        INTO batchId, batchConsumed, cardsCreated, batchPrintStatus 
        FROM gaming_playercard_batches 
		WHERE (`type` = 1 OR `type` = 2) AND playerCardNumber BETWEEN from_card_number AND to_card_number;
 
		IF(batchId IS NULL) THEN
			SET statusCode=8;
			LEAVE root;
		END IF;
		
        IF(batchPrintStatus != 1) THEN
			SET statusCode=9;
			LEAVE root;
		END IF;


    END IF; 
    
    
    SELECT current_real_balance, client_stat_id 
    INTO currentBalance, clientStatId 
    FROM gaming_client_stats 
	WHERE client_id = playerId AND is_active;
        
    IF(currentBalance < fee)THEN
		SET statusCode=5;
		LEAVE root;
	END IF;
     
    IF(expirationDate IS NULL) THEN
		SET expirationUnlimited = 1;
    END IF; 
 
	 
    IF(fee > 0) THEN
		
        CALL TransactionAdjustRealMoney(sessionID, clientStatId, 0 - fee , 'Player Card Fee'  , 'PlayerCardFee'  , UUID(), 1, 0, NULL, transactionStatusCode);
        IF(transactionStatusCode <> 0)THEN
			SET statusCode=6;
			LEAVE root;
		END IF;
        
	END IF;
    
    INSERT INTO gaming_playercard_cards (playercard_cards_id, client_id, batch_id, expiration_date, date_assigned, card_status, printing_status, fee_issued, is_expiration_unlimited)
	VALUES (playerCardNumber, playerId, batchId, expirationDate, nowDateTime, 0, printStatus, fee, expirationUnlimited);
    
    SET lastInsertID = playerCardNumber;
     
    UPDATE gaming_playercard_batches 
    SET cards_consumed = batchConsumed + 1 
	WHERE playercard_batch_id = batchId;
          
	IF(batchConsumed + 1 = cardsCreated) THEN
        UPDATE gaming_playercard_batches 
        SET consumed_date = nowDateTime
		WHERE playercard_batch_id = batchId;
	END IF;
    
	CALL NotificationEventCreate(612, playerCardNumber, playerId, 0);
     
END root$$

DELIMITER ;

