DROP procedure IF EXISTS `PaymentCalculateCharge`;

DELIMITER $$
CREATE PROCEDURE `PaymentCalculateCharge` (transactionType VARCHAR(20), paymentMethodID BIGINT(20), currencyID BIGINT(20), transactionAmount DECIMAL(14,0), forceIncludeAmount TINYINT(1),
OUT chargeSettingID BIGINT(20), OUT calculatedAmount  DECIMAL(18, 5), OUT chargeAmount DECIMAL(18, 5), OUT overAmount TINYINT(1))
root:BEGIN

	DECLARE minRange, maxRange, percentage, fixedAmount, minLimit, maxLimit,minCharge DECIMAL(18, 5) DEFAULT 0;
    
	SELECT  pcs.payment_charge_setting_id, pcr.min_range, IFNULL(pcr.max_range, transactionAmount + 1), pcr.percentage, pcr.fixed_amount, pcr.min_limit, pcr.max_limit, pcs.over_amount
    INTO chargeSettingID,minRange, maxRange, percentage, fixedAmount, minLimit, maxLimit, overAmount
    FROM payment_charge_settings AS pcs
	JOIN payment_charge_ranges AS pcr ON pcs.payment_charge_setting_id = pcr.payment_charge_setting_id AND pcs.is_active = 1 AND pcs.operator_allow_charge AND pcr.currency_id = currencyID 
	STRAIGHT_JOIN payment_methods AS pm ON pcs.payment_method_id = pm.payment_method_id AND pm.payment_method_id = paymentMethodID AND pm.is_active = 1
    JOIN gaming_payment_transaction_type AS gptt ON pcs.payment_transaction_type_id = gptt.payment_transaction_type_id 
		AND gptt.name = transactionType 
    WHERE pcr.min_range <= transactionAmount AND transactionAmount < IFNULL(pcr.max_range, transactionAmount + 1) 
	AND CASE  pcs.payment_transaction_type_id 
	WHEN 1 THEN pm.support_charges_on_deposit = 1 
	WHEN 2 THEN pm.support_charges_on_withdraw = 1 
	ELSE FALSE
	END;
    
    IF(chargeSettingID IS NULL) THEN
        SELECT 0 , 0 , transactionAmount, 0
        INTO chargeAmount, chargeSettingID, calculatedAmount, overAmount;
        LEAVE root;
	END IF;
    
    IF(overAmount = 0 OR forceIncludeAmount = 1) THEN 
		SET minCharge = GREATEST((transactionAmount - fixedAmount) / (1 + percentage),minLimit);
		SET chargeAmount = ROUND(transactionAmount - LEAST(minCharge, COALESCE(maxLimit,minCharge)), 0);
		SET calculatedAmount = transactionAmount - chargeAmount;
	ELSE 
		SET minCharge = GREATEST((transactionAmount * percentage + fixedAmount),minLimit);
		SET chargeAmount= ROUND(LEAST(minCharge, COALESCE(maxLimit,minCharge)), 0);
		SET calculatedAmount = transactionAmount;
	END IF;
END$$

DELIMITER ;