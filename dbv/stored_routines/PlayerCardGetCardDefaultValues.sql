DROP procedure IF EXISTS `PlayerCardGetCardDefaultValues`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerCardGetCardDefaultValues`(clientID BIGINT)
BEGIN
    
	DECLARE availableCards, autoCreateBatch, cardsCheck, fromCard, toCard, expirationDate, batchConsumed INT DEFAULT 0;
    DECLARE autoissueVirtualCard TINYINT(1) DEFAULT 0;
    DECLARE timesLostBeforeFee, lastCardStatus, timesLost, monthsBeforeExpiration  INT DEFAULT 0;
    DECLARE feeDefault, feeLost, feeExpiration, fee DECIMAL(18,5);
	
    SELECT MAX(IF(name = 'fee_default', value_dec, NULL)), 
		   MAX(IF(name = 'fee_lost', value_dec, NULL)), 
		   MAX(IF(name = 'fee_expiration', value_dec, NULL)),
		   MAX(IF(name = 'times_lost_before_fee', value_int, NULL)), 
           MAX(IF(name = 'months_before_expiration', value_int, NULL)), 
           MAX(IF(name = 'autoissue_virtual_card', value_int, NULL))    
		INTO feeDefault, feeLost, feeExpiration, timesLostBeforeFee, monthsBeforeExpiration, autoissueVirtualCard
		FROM gaming_playercard_settings;
	
    SET fee = feeDefault;
    
    SELECT IFNULL(card_status, 0) INTO lastCardStatus FROM gaming_playercard_cards FORCE INDEX (idx_clientid) WHERE client_id = clientID ORDER BY playercard_cards_id DESC LIMIT 1;
    
    IF(lastCardStatus = 2) THEN
		
		SELECT COUNT(1) INTO timesLost FROM gaming_playercard_cards FORCE INDEX (idx_clientid) WHERE client_id = clientID AND (card_status = 2 or card_status = 3);
		IF(timesLost >= timesLostBeforeFee) THEN
			SET fee = feeLost;
        END IF; 
        
	ELSEIF(lastCardStatus = 1) THEN
		SET fee = feeExpiration;
	END IF; 
    
    SELECT fee AS 'fee', 
		IF(monthsBeforeExpiration = 0, NULL,
			(DATE_ADD(CURDATE(), INTERVAL monthsBeforeExpiration MONTH))) AS expiration_date, 
		autoissueVirtualCard AS autoissue_virtual_card;
    
END$$

DELIMITER ;

