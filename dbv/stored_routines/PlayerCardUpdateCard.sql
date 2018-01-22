DROP procedure IF EXISTS `PlayerCardUpdateCard`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerCardUpdateCard`(clientID BIGINT, playerCardNumber BIGINT, cardStatus TINYINT(4), fee DECIMAL(18,5), expirationDate DATETIME, printStatus TINYINT(4), sessionID BIGINT, OUT statusCode INT)
root: BEGIN
 
    DECLARE checkCards, v_numofcards  INT DEFAULT 0;
    DECLARE expirationCurrentDate  DATETIME;
    DECLARE batchId, clientStatId, cardNumberCheck, transactionStatusCode BIGINT DEFAULT 0;
    DECLARE printingStatus, batchType, cardCurrentStatus TINYINT(4) DEFAULT 0;
    DECLARE cardExists, expirationUnlimited TINYINT(1) DEFAULT 0;
    DECLARE v_daysBeforeExpireNotification, v_monthsBeforeExpiration, v_autoissueVirtualCard INT DEFAULT 0;
    DECLARE currentBalance DECIMAL(18,5);
	DECLARE v_curdate DATE DEFAULT CURDATE();
    SET statusCode=0;
   
	SELECT 1, c.batch_id, c.expiration_date, c.printing_status, b.type, c.card_status, c.is_expiration_unlimited
		INTO cardExists, batchId, expirationCurrentDate, printingStatus, batchType, cardCurrentStatus,expirationUnlimited
		FROM gaming_playercard_cards c, gaming_playercard_batches b 
        WHERE c.batch_id = b.playercard_batch_id AND c.playercard_cards_id = playerCardNumber AND c.client_id = clientID;
 
	IF(cardExists = 0) THEN
		SET statusCode=1;
		LEAVE root; 
	END IF;

	SELECT MAX(IF(name = 'notification_days_before_expiration', value_int, NULL)), MAX(IF(name = 'autoissue_virtual_card', value_int, NULL)), MAX(IF(name = 'months_before_expiration', value_int, NULL)) 
    INTO v_daysBeforeExpireNotification, v_autoissueVirtualCard, v_monthsBeforeExpiration
		FROM gaming_playercard_settings;
 
	IF(cardCurrentStatus = 1) THEN
		SET statusCode=4;
		LEAVE root; 
	END IF;  
	
    IF(cardStatus = 0) THEN
		SELECT COUNT(1) INTO checkCards FROM gaming_playercard_cards WHERE client_id = clientID AND playerCardNumber <>  playercard_cards_id AND card_status  = 0;
		IF(checkCards > 0)THEN
			SET statusCode=2;
			LEAVE root;
		END IF; 
	ELSEIF(cardStatus = 2 AND printingStatus != 1)THEN
		SET statusCode=6;
		LEAVE root;
	END IF;  
     
   	IF(cardStatus = 0 AND cardCurrentStatus = 2) THEN
		
    	SELECT playercard_cards_id INTO cardNumberCheck FROM gaming_playercard_cards WHERE client_id = clientID ORDER BY playercard_cards_id DESC LIMIT 1;
        IF(cardNumberCheck != playerCardNumber)THEN
			SET statusCode=7;
			LEAVE root;
		END IF; 
	END IF; 	
	
    IF(expirationDate IS NULL) THEN
		IF(cardStatus = 1) THEN
			SET expirationDate = v_curdate;
		ELSEIF(cardStatus = 2) THEN
        	SET expirationDate = expirationCurrentDate;
		ELSE
			SET expirationUnlimited = 1;
		END IF;
         
	ELSE
		SET expirationUnlimited = 0;
	END IF;     
 
	IF(expirationDate < v_curdate) THEN 
		SET statusCode=3;
		LEAVE root;
	END IF; 
      
    
    IF (printStatus IS NOT NULL AND (batchType = 1 OR batchType = 2)) THEN
		SET statusCode=5;
		LEAVE root;
	END IF; 
  
	IF(printStatus IS NULL) THEN
		SET printStatus = printingStatus;
    END IF;
    
    IF(batchType <> 0 OR printStatus IS NULL) THEN
		SET printStatus = printingStatus;
	END IF; 
     
    IF(cardStatus != cardCurrentStatus) THEN
		
		CALL NotificationEventCreate(608, playerCardNumber, clientID, 0);
    END IF;
     IF(printStatus != printingStatus) THEN
		 
        CALL NotificationEventCreate(609, playerCardNumber, clientID, 0);
    END IF;
    IF(printStatus IS NOT NULL AND printStatus = 1 AND batchType = 0) THEN
		
		CALL NotificationEventCreate(610, playerCardNumber, clientID, 0);
    END IF;
    
    
    
     IF(fee IS NOT NULL AND fee > 0) THEN
		 
       SELECT current_real_balance, client_stat_id INTO currentBalance, clientStatId FROM  gaming_client_stats 
		WHERE client_id = clientID;
		IF(currentBalance < fee)THEN
			SET statusCode=9;
			LEAVE root;
		END IF;
        
        CALL TransactionAdjustRealMoney(sessionID, clientStatId, 0 - fee , 'Player Card Fee'  , 'PlayerCardFee'  , UUID(), 1, 0, NULL, transactionStatusCode);
        IF(transactionStatusCode <> 0)THEN
			SET statusCode=8;
			LEAVE root;
		END IF;
	END IF;
    
	UPDATE  gaming_playercard_cards
	SET expiration_date  = DATE(expirationDate),
		card_status = cardStatus,
		printing_status = printStatus,
        is_expiration_unlimited = expirationUnlimited
	WHERE playercard_cards_id = playerCardNumber;
    
 
END root$$

DELIMITER ;

