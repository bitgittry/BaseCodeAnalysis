DROP function IF EXISTS `PaymentGetPaymentKeyFromBit8PaymentMethodID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PaymentGetPaymentKeyFromBit8PaymentMethodID`(bit8PaymentMethodID BIGINT) RETURNS varchar(40) CHARSET utf8
BEGIN
  -- First Version 

  DECLARE paymentMethodID BIGINT DEFAULT NULL;

  SELECT payment_methods.payment_method_id INTO paymentMethodID
  FROM gaming_payment_method
  JOIN payment_methods ON gaming_payment_method.payment_gateway_method_name=payment_methods.name
  WHERE gaming_payment_method.payment_method_id=bit8PaymentMethodID
  LIMIT 1;

  RETURN PaymentGetPaymentKey(IFNULL(paymentMethodID, 1));

END$$

DELIMITER ;

