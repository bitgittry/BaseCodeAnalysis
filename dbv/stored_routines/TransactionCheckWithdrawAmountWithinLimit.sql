
DROP function IF EXISTS `TransactionCheckWithdrawAmountWithinLimit`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `TransactionCheckWithdrawAmountWithinLimit`(clientStatID BIGINT, paymentMethodID BIGINT, varAmount DECIMAL(18, 5), balanceAccountID BIGINT) RETURNS int(11)
BEGIN
  
  
  

  DECLARE currencyIDCheck BIGINT DEFAULT -1;
  DECLARE beforeKYCWithdrawalLimit DECIMAL(18, 5) DEFAULT NULL;
  DECLARE beforeKYCWithdrawalLimitEnabled, kycRequiredPerPlayerAccount, kycLimitExceeded, transferLimitsEnabled TINYINT(1) DEFAULT 0;
  DECLARE countryCode CHAR(2) DEFAULT NULL;
  DECLARE currencyCode CHAR(3) DEFAULT NULL;
  DECLARE countryID BIGINT DEFAULT -1;

  SET @clientStatID = clientStatID; 
  SET @paymentMethodID = paymentMethodID; 
  SET @varAmount = varAmount; 
  
  SET @dateTransactionFilter = (SELECT value_date FROM gaming_settings WHERE name='SYSTEM_END_DATE'); 
  SET @dateDayFilter = CURDATE();
  SET @dateWeekFilter = DateGetWeekStart();
  SET @dateMonthFilter = DateGetMonthStart();  
  SET @paymentMethodIDCheck = 0;
  SET @minAmount = 0;
  SET @maxAmount = 0;

  SELECT value_bool INTO transferLimitsEnabled FROM gaming_settings WHERE name='TRANSFER_LIMITS_ENABLED';	 
  SELECT value_bool INTO beforeKYCWithdrawalLimitEnabled FROM gaming_settings WHERE name='TRANSFER_BEFORE_KYC_DEPOSIT_LIMIT_ENABLED';
  SELECT value_bool INTO kycRequiredPerPlayerAccount FROM gaming_settings WHERE name='TRANSFER_KYC_REQUIRED_PER_PLAYER_ACCOUNT';
  
  SELECT gaming_payment_amounts.currency_id, before_kyc_withdrawal_limit, min_withdrawal, max_withdrawal
  INTO currencyIDCheck, beforeKYCWithdrawalLimit, @minAmount, @maxAmount
  FROM gaming_payment_amounts
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_payment_amounts.currency_id;
	
  IF (currencyIDCheck=-1) THEN
	RETURN 1;
  END IF;

  
  SELECT IFNULL(gaming_currency.currency_code,'---'), IFNULL(gaming_countries.country_code,'--'), IFNULL(gaming_countries.country_id, -1)
  INTO currencyCode, countryCode, countryID
  FROM gaming_client_stats
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary=1
  LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
  WHERE gaming_client_stats.client_stat_id=clientStatID;	

  IF (transferLimitsEnabled=1) THEN

	  SELECT
		PlayerStatus.payment_method_id,
		PlayerStatus.admin_min_limit AS min_amount,
		MIN(PlayerStatus.remaining) AS max_amount  
	  INTO @paymentMethodIDCheck, @minAmount, @maxAmount
	  FROM
	  (
		
		SELECT 
		  gaming_client_stats.client_stat_id, 
		  gaming_clients.client_id,
		  gaming_transfer_limits.transfer_limit_id,
		  gaming_payment_method.payment_method_id,
		  gaming_payment_method.name AS payment_method,
		  
		  gaming_interval_type.name AS interval_type, 
		  gaming_payment_amounts.min_withdrawal AS admin_min_limit,
		  LEAST(gaming_payment_amounts.max_withdrawal, IFNULL(gaming_transfer_limit_amounts.admin_max_amount,gaming_payment_amounts.max_withdrawal)) AS admin_max_limit,
		  IFNULL(CurrentValue.withdrawn_amount,0) AS current_value,
		  LEAST(gaming_payment_amounts.max_withdrawal, IFNULL(gaming_transfer_limit_amounts.admin_max_amount,gaming_payment_amounts.max_withdrawal)) - IFNULL(CurrentValue.withdrawn_amount,0) AS remaining
		FROM gaming_client_stats 
		JOIN gaming_clients ON
		  gaming_client_stats.client_stat_id=@clientStatID AND
		  gaming_client_stats.client_id=gaming_clients.client_id
		JOIN gaming_currency 
		  ON gaming_client_stats.currency_id=gaming_currency.currency_id
		JOIN gaming_interval_type
		  ON gaming_interval_type.is_transfer_limit=1
		JOIN gaming_payment_transaction_type
		  ON gaming_payment_transaction_type.name='Withdrawal'
		JOIN gaming_payment_amounts 
		  ON gaming_payment_amounts.currency_id=gaming_client_stats.currency_id 
		JOIN gaming_payment_method ON gaming_payment_method.can_withdraw=1 AND is_payment_gateway_method=1 AND gaming_payment_method.is_active=1
		LEFT JOIN gaming_transfer_limits ON 
		  gaming_transfer_limits.client_segment_id=gaming_clients.client_segment_id AND 
		  gaming_transfer_limits.interval_type_id=gaming_interval_type.interval_type_id AND
		  gaming_transfer_limits.payment_method_id = gaming_payment_method.payment_method_id AND
		  gaming_transfer_limits.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id 
		LEFT JOIN gaming_transfer_limit_amounts ON  
		  gaming_transfer_limits.transfer_limit_id=gaming_transfer_limit_amounts.transfer_limit_id AND 
		  gaming_transfer_limit_amounts.currency_id=gaming_client_stats.currency_id
		LEFT JOIN
		(
		  SELECT 
			transfer_limit_id, 
			DL.payment_method_id,
			interval_type_id, 
			SUM(IFNULL(BalanceTransactions.amount,0)) AS withdrawn_amount 
		  FROM
		  (
		  
			SELECT 
			  gaming_transfer_limits.transfer_limit_id AS transfer_limit_id,
			  gaming_interval_type.interval_type_id,
			  gaming_payment_method.payment_method_id,
			  CASE 
				WHEN gaming_interval_type.name='Transaction' THEN @dateTransactionFilter
				WHEN gaming_interval_type.name='Day' THEN CURDATE()
				WHEN gaming_interval_type.name='Week' THEN DateGetWeekStart()
				WHEN gaming_interval_type.name='Month' THEN DateGetMonthStart()
				WHEN gaming_interval_type.name='Year' THEN DATE_FORMAT(NOW() ,'%Y-01-01')
			  END AS transaction_filter_start_date 
			FROM gaming_client_stats 
			JOIN gaming_clients ON
			  gaming_client_stats.client_stat_id=@clientStatID AND
			  gaming_client_stats.client_id=gaming_clients.client_id
			JOIN gaming_interval_type
			  ON gaming_interval_type.is_transfer_limit=1
			JOIN gaming_payment_transaction_type
			  ON gaming_payment_transaction_type.name='Withdrawal'
			JOIN gaming_payment_method ON gaming_payment_method.can_withdraw=1 AND is_payment_gateway_method=1 AND gaming_payment_method.is_active=1
			LEFT JOIN gaming_transfer_limits ON 
			  gaming_transfer_limits.client_segment_id=gaming_clients.client_segment_id AND 
			  gaming_transfer_limits.interval_type_id=gaming_interval_type.interval_type_id AND
			  gaming_transfer_limits.payment_method_id = gaming_payment_method.payment_method_id AND
			  gaming_transfer_limits.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id 
		  ) AS DL
		  LEFT JOIN 
		  (
			SELECT gaming_balance_history.balance_history_id, amount, timestamp, gaming_payment_method.payment_method_id  
			FROM gaming_balance_history
			JOIN gaming_payment_transaction_type ON 
			  gaming_balance_history.client_stat_id=@clientStatID AND 
			  gaming_payment_transaction_type.name='Withdrawal' AND
			  gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
			JOIN gaming_payment_transaction_status ON 
			  gaming_payment_transaction_status.is_withdrawal_limit_capture=1 AND
			  gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id 
			JOIN gaming_payment_method ON 
			  gaming_payment_method.can_withdraw=1 AND 
			  ((gaming_payment_method.is_sub_method=0 AND gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id) OR
			   (gaming_payment_method.is_sub_method=1 AND gaming_balance_history.sub_payment_method_id=gaming_payment_method.payment_method_id))
			  
			WHERE 
			  gaming_balance_history.pending_request=0  
		  ) AS BalanceTransactions ON 
			DL.payment_method_id=BalanceTransactions.payment_method_id AND BalanceTransactions.timestamp>=DL.transaction_filter_start_date 
		  GROUP BY DL.payment_method_id, DL.interval_type_id 
		) AS CurrentValue ON 
		  gaming_payment_method.payment_method_id=CurrentValue.payment_method_id AND 
		  gaming_interval_type.interval_type_id=CurrentValue.interval_type_id
	  ) AS PlayerStatus  
      JOIN gaming_clients ON gaming_clients.client_id=PlayerStatus.client_id
	  JOIN gaming_payment_method ON  
		gaming_payment_method.payment_method_id=@paymentMethodID AND
		gaming_payment_method.is_active AND gaming_payment_method.can_withdraw=1 AND is_payment_gateway_method=1 AND
		PlayerStatus.payment_method_id=gaming_payment_method.payment_method_id 
	  LEFT JOIN gaming_client_payment_info ON gaming_clients.client_id=gaming_client_payment_info.client_id AND gaming_payment_method.payment_method_id=gaming_client_payment_info.payment_method_id 
	  LEFT JOIN gaming_payment_method_currencies AS currency_permissions ON currency_permissions.payment_method_id=gaming_payment_method.payment_method_id AND currency_permissions.currency_code=currencyCode
	  LEFT JOIN gaming_payment_method_countries AS country_permissions ON country_permissions.payment_method_id=gaming_payment_method.payment_method_id AND country_permissions.country_code=countryCode
	  LEFT JOIN gaming_country_payment_info AS country_payment_permissions ON country_payment_permissions.country_id=countryID AND country_payment_permissions.payment_method_id=gaming_payment_method.payment_method_id
	  WHERE (gaming_client_payment_info.client_id IS NULL OR gaming_client_payment_info.is_disabled=0) 
		AND (gaming_payment_method.currency_inclusion_type=0 OR (gaming_payment_method.currency_inclusion_type=1 AND currency_permissions.payment_method_id IS NOT NULL) OR (gaming_payment_method.currency_inclusion_type=2 AND currency_permissions.payment_method_id IS NULL))
		AND (gaming_payment_method.country_inclusion_type=0 OR (gaming_payment_method.country_inclusion_type=1 AND country_permissions.payment_method_id IS NOT NULL) OR (gaming_payment_method.country_inclusion_type=2 AND country_permissions.payment_method_id IS NULL))
		AND (country_payment_permissions.payment_method_id IS NULL OR (country_payment_permissions.is_disabled=0 AND country_payment_permissions.is_withdrawal_disabled=0)) 
	  GROUP BY PlayerStatus.payment_method_id;
	
  ELSE
	  SELECT gaming_payment_method.payment_method_id, gaming_payment_amounts.min_withdrawal, gaming_payment_amounts.max_withdrawal
	  INTO @paymentMethodIDCheck, @minAmount, @maxAmount
	  FROM gaming_client_stats
	  JOIN gaming_clients ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.client_id=gaming_clients.client_id
      JOIN gaming_payment_amounts ON gaming_payment_amounts.currency_id=gaming_client_stats.currency_id
	  JOIN gaming_payment_method ON gaming_payment_method.payment_method_id=@paymentMethodID AND gaming_payment_method.is_payment_gateway_method=1 AND gaming_payment_method.is_active=1 AND gaming_payment_method.can_withdraw=1
	  LEFT JOIN gaming_client_payment_info ON gaming_clients.client_id=gaming_client_payment_info.client_id AND gaming_payment_method.payment_method_id=gaming_client_payment_info.payment_method_id 
	  LEFT JOIN gaming_payment_method_currencies AS currency_permissions ON currency_permissions.payment_method_id=gaming_payment_method.payment_method_id AND currency_permissions.currency_code=currencyCode
	  LEFT JOIN gaming_payment_method_countries AS country_permissions ON country_permissions.payment_method_id=gaming_payment_method.payment_method_id AND country_permissions.country_code=countryCode
	  LEFT JOIN gaming_country_payment_info AS country_payment_permissions ON country_payment_permissions.country_id=countryID AND country_payment_permissions.payment_method_id=gaming_payment_method.payment_method_id
	  WHERE (gaming_client_payment_info.client_id IS NULL OR gaming_client_payment_info.is_disabled=0) 
		AND (gaming_payment_method.currency_inclusion_type=0 OR (gaming_payment_method.currency_inclusion_type=1 AND currency_permissions.payment_method_id IS NOT NULL) OR (gaming_payment_method.currency_inclusion_type=2 AND currency_permissions.payment_method_id IS NULL))
		AND (gaming_payment_method.country_inclusion_type=0 OR (gaming_payment_method.country_inclusion_type=1 AND country_permissions.payment_method_id IS NOT NULL) OR (gaming_payment_method.country_inclusion_type=2 AND country_permissions.payment_method_id IS NULL))
		AND (country_payment_permissions.payment_method_id IS NULL OR (country_payment_permissions.is_disabled=0 AND country_payment_permissions.is_withdrawal_disabled=0));
	  
  END IF;

  IF (@paymentMethodID <> @paymentMethodIDCheck) THEN
		RETURN 1;
	  END IF;

  IF (@varAmount < @minAmount) THEN
    RETURN 2;
  END IF;
  
  IF (@varAmount > @maxAmount) THEN
    RETURN 3;
  END IF;
  

  IF (beforeKYCWithdrawalLimitEnabled=1) THEN
    SELECT IF(
      (kycRequiredPerPlayerAccount=0 AND gaming_clients.is_kyc_checked=0 AND (gaming_client_stats.withdrawn_amount+gaming_client_stats.withdrawal_pending_amount+varAmount>beforeKYCWithdrawalLimit)) OR 
      (kycRequiredPerPlayerAccount=1 AND balanceAccountID IS NOT NULL AND (gaming_clients.is_kyc_checked=0 OR gaming_balance_accounts.kyc_checked=0) AND (gaming_balance_accounts.withdrawn_amount+gaming_balance_accounts.withdrawal_pending_amount+varAmount>beforeKYCWithdrawalLimit)) 
        , 1, 0) AS kyc_limit_exceeded INTO kycLimitExceeded
    FROM gaming_client_stats
    JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
    LEFT JOIN gaming_balance_accounts ON gaming_balance_accounts.balance_account_id=balanceAccountID
    WHERE gaming_client_stats.client_stat_id=clientStatID;
    
    IF (kycLimitExceeded) THEN
      RETURN 4;
    END IF;
  END IF;
  
  RETURN 0;
END$$

DELIMITER ;

