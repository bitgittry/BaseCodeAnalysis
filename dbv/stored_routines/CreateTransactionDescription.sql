DROP FUNCTION IF EXISTS `CreateTransactionDescription`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1`  FUNCTION `CreateTransactionDescription`(amount DECIMAL(18,5), chargedAmount DECIMAL(18,5), displayName VARCHAR(255), currencyId BIGINT)
	RETURNS VARCHAR(255) CHARSET utf8
BEGIN
	DECLARE currencySymbol, details VARCHAR(255);
	
	IF (amount IS NULL OR amount = 0 OR chargedAmount IS NULL OR chargedAmount = 0 OR NOT (displayName = 'Deposit' OR displayName like '%Withdrawal%')) THEN
		RETURN displayName;
	END IF;
	
	SELECT IF(symbol = '?' OR symbol = 'NONE', '', symbol)
	INTO currencySymbol
	FROM gaming_currency
	WHERE currency_id = currencyId;
		
	RETURN CONCAT(displayName, ' - ', currencySymbol, ROUND(amount/100,2), '; Service Charge ',  currencySymbol, ROUND(chargedAmount/100,2), '; Total Amount ', currencySymbol, ROUND((amount + chargedAmount)/100,2));
	
END$$

DELIMITER ;