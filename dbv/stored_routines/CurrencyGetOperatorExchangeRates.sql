DROP procedure IF EXISTS `CurrencyGetOperatorExchangeRates`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CurrencyGetOperatorExchangeRates`(operatorID BIGINT, evenExchangeRateOnly TINYINT(1), OUT statusCode INT)
BEGIN
	SELECT currency_id  
  FROM gaming_operators WHERE operator_id=operatorID; 
  SELECT gaming_currency.currency_id, currency_code, gaming_currency.name, name_short, symbol, operator_currency_id, exchange_rate 
  FROM gaming_currency 
  JOIN gaming_operator_currency ON gaming_currency.currency_id=gaming_operator_currency.currency_id 
    AND gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.is_active=1
    AND (gaming_currency.exchange_rate_only=0 OR evenExchangeRateOnly=1);
    
  SELECT gaming_currency.currency_id, currency_code, gaming_currency.name, name_short, symbol, operator_currency_id, exchange_rate 
  FROM gaming_currency 
  JOIN gaming_operator_currency ON gaming_currency.currency_id=gaming_operator_currency.currency_id 
    AND gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.is_active=0
    AND (gaming_currency.exchange_rate_only=0 OR evenExchangeRateOnly=1);
    
  SET statusCode=0; 
  
END$$

DELIMITER ;

