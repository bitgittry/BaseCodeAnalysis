DROP procedure IF EXISTS `TransactionPaymentMethodSetDefaultWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionPaymentMethodSetDefaultWithdrawal`(paymentMethodID BIGINT, OUT statusCode INT)
root:BEGIN

  DECLARE v_paymentMethodID BIGINT;

  SELECT payment_method_id INTO v_paymentMethodID FROM gaming_payment_method WHERE payment_method_id = paymentMethodID AND is_active = 1;
  
  IF (v_paymentMethodID is null) THEN
    SET statusCode = 2907 /*Payment_Invalid_PaymentMethod_Or_Inactive*/;
    LEAVE root;
  END IF;

  UPDATE gaming_payment_method SET is_default_withdrawal = 0 WHERE is_default_withdrawal = 1;

  UPDATE gaming_payment_method SET is_default_withdrawal = 1 WHERE payment_method_id = paymentMethodID;

  SET statusCode = 0;
END root$$

DELIMITER ;
