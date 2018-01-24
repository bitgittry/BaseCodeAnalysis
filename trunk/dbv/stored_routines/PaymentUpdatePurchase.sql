DROP procedure IF EXISTS `PaymentUpdatePurchase`;

DELIMITER $$
CREATE PROCEDURE `PaymentUpdatePurchase` ( clientStatID BIGINT(20), paymentKey VARCHAR(80), transactionType VARCHAR(20), paymentTransactionTypeID BIGINT(20), amount DECIMAL(14,0), paymentMethodID BIGINT(20), bit8PaymentMethodID BIGINT(20), clientStatBalanceUpdated TINYINT(1))
root:BEGIN
 
 DECLARE chargeSettingID, currencyID BIGINT DEFAULT -1;
 DECLARE calculatedAmount, chargeAmount DECIMAL(14,0);
 DECLARE overAmount TINYINT(1) DEFAULT 0;
 
 SELECT IFNULL(paymentMethodID, pp.payment_method_id), gc.currency_id, IFNULL(amount, pp.amount_total)
 INTO paymentMethodID, currencyID, amount
 FROM payment_purchases AS pp
 LEFT JOIN gaming_currency AS gc ON gc.currency_code = pp.currency_code
 WHERE pp.payment_key=paymentKey AND pp.client_stat_id=clientStatID;
 
 CALL PaymentCalculateCharge(transactionType, paymentMethodID, currencyID, amount, 0, chargeSettingID, calculatedAmount, chargeAmount, overAmount);
 
 UPDATE gaming_balance_history AS gbh
 LEFT JOIN gaming_payment_method AS gpm ON gpm.payment_method_id=bit8PaymentMethodID
 SET gbh.payment_transaction_type_id=paymentTransactionTypeID, gbh.amount=calculatedAmount, 
     gbh.payment_method_id=COALESCE(gpm.parent_payment_method_id, gpm.payment_method_id, gbh.payment_method_id), gbh.sub_payment_method_id=IFNULL(gpm.payment_method_id, gbh.sub_payment_method_id),
	 gbh.client_stat_balance_updated = IFNULL(clientStatBalanceUpdated, gbh.client_stat_balance_updated),
     gbh.is_processed = IFNULL(clientStatBalanceUpdated, gbh.client_stat_balance_updated),
	 gbh.charge_amount = chargeAmount, 
	 gbh.payment_charge_setting_id = chargeSettingID
 WHERE gbh.unique_transaction_id=paymentKey AND gbh.client_stat_id=clientStatID;
 
 
 UPDATE payment_purchases AS pp
 SET pp.transaction_type=transactionType, pp.amount_total=calculatedAmount + chargeAmount, pp.payment_method_id=paymentMethodID, pp.charge_amount = chargeAmount, pp.payment_charge_setting_id = chargeSettingID
 WHERE pp.payment_key=paymentKey AND pp.client_stat_id=clientStatID;
 
END$$

DELIMITER ;