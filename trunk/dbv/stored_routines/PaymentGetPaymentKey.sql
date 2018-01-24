DROP function IF EXISTS `PaymentGetPaymentKey`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PaymentGetPaymentKey`(paymentMethodID BIGINT) RETURNS varchar(40) CHARSET utf8
BEGIN
  
  DECLARE paymentCode CHAR(2) DEFAULT '';
  DECLARE maxPaymentKey BIGINT DEFAULT 10000000000; 
  DECLARE tryNumber INT DEFAULT 0;
  DECLARE isNumeric TINYINT(1) DEFAULT 0;
  DECLARE brandPrefix VARCHAR(5) DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLSTATE '23000' SET @alreadyExists = 1;

  SELECT code, max_payment_key 
  INTO paymentCode, maxPaymentKey
  FROM payment_methods
  WHERE payment_method_id=paymentMethodID;
  
  SELECT value_bool INTO isNumeric FROM gaming_settings WHERE name='PAYMENT_KEY_IS_NUMERIC';
  SELECT TRIM(IFNULL(value_string,'')) INTO brandPrefix FROM gaming_settings WHERE name='BRAND_PREFIX';

  
  SET @minNum=IF(isNumeric, 100000, 0);
  SET @maxNum= IFNULL(maxPaymentKey, 1000000000000000); 

  REPEAT   
    SET @alreadyExists=0;
    SET tryNumber=tryNumber+1;

    IF (tryNumber>3) THEN
      SET @paymentKey=CONCAT(@paymentKey,tryNumber);
    ELSE
	  IF (isNumeric) THEN
		SET @paymentKey=CONCAT(brandPrefix, paymentCode, FLOOR(@minNum + RAND() * (@maxNum - @minNum)));
	  ELSE
		SET @paymentKey=CONCAT(brandPrefix, paymentCode, LPAD(FLOOR(@minNum + RAND() * (@maxNum - @minNum)), LOG10(@maxNum), '0'));
	  END IF;
    END IF;
    
    INSERT INTO payment_keys (payment_key, date_created, try_number) VALUES (@paymentKey, NOW(), tryNumber);

  UNTIL @alreadyExists=0 OR tryNumber>3
  END REPEAT;
  
  RETURN @paymentKey;
END$$

DELIMITER ;