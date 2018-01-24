DROP view IF EXISTS `vm_get_deposits_from_payment_methods`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`localhost` VIEW `vm_get_deposits_from_payment_methods` AS

    SELECT 
        `gaming_balance_manual_transactions`.`payment_method_id` AS `paymentMethodID`,        
        `gaming_balance_history`.`balance_history_id` AS `PaymentTransactionID`,
        `gaming_balance_manual_transactions`.`client_id` AS `ClientID`,
        ROUND(IFNULL(`gaming_balance_manual_transactions`.`amount`, 0), 2) AS `Amount`,
        `gaming_payment_transaction_type`.`name` AS `TransactionType`,
        `gaming_payment_transaction_status`.`name` AS `TransactionStatus`,
        `gaming_payment_method`.`name` AS `PaymentMethod`,
        `gaming_balance_manual_transactions`.`reason` AS `StatusReason`,
        ROUND(`gaming_client_stats`.`current_real_balance`,2) AS `PlayerBalance`,
        ROUND((IFNULL(`gaming_balance_manual_transactions`.`amount`,0) / CAST( IFNULL(`exrate`.`exchange_rate` ,  `gaming_operator_currency`.`exchange_rate` )  AS decimal  (18,5) )  ),  2) AS `AmountBase`,  
        ROUND((`gaming_balance_history`.`balance_real_after` / CAST( IFNULL(`exrate`.`exchange_rate` ,  `gaming_operator_currency`.`exchange_rate` )  AS decimal  (18,5) )), 2) AS `BalanceRealBase`,
        `gaming_clients`.`name` AS `PlayerName`,
        `gaming_clients`.`surname` AS `PlayerSurname`,
        `gaming_balance_manual_transactions`.`transaction_date` AS `RequestDate`,
        `gaming_payment_file_import_summary`.`timestamp` AS `ProcessedDate`,
        `gaming_currency`.`currency_code` AS `CurrencyCode`,
        `gaming_balance_manual_transactions`.`external_reference` AS `GwTransactionKey`,
        `gaming_balance_accounts`.`account_reference` AS `AccountReference`,
        IFNULL(`gaming_transaction_reconcilation_statuses`.`name`,'Not Set') AS `ReconciliationStatus`,
        `gaming_payment_file_import_summary`.`batch_journal_id` AS `BatchJournalID`,
        CAST(IFNULL(`exrate`.`exchange_rate`,`gaming_operator_currency`.`exchange_rate`)  AS DECIMAL (18 , 5 )) AS `exchangerate`,
        `gaming_balance_withdrawal_requests`.`pay_now` AS `PayNow`,
        IF(`gaming_balance_manual_transactions`.`request_creator_type_id` = 2, `users_main`.`username`, `gaming_balance_request_creator_types`.`name`) AS `CreatedBy`,
        `gaming_balance_request_creator_types`.`name` AS `CreatedByEntity`
    FROM
        (((((((((((((((`gaming_balance_manual_transactions`
        STRAIGHT_JOIN `gaming_payment_method` ON ((`gaming_balance_manual_transactions`.`payment_method_id` = `gaming_payment_method`.`payment_method_id`)))
        STRAIGHT_JOIN `gaming_payment_transaction_type` ON ((`gaming_balance_manual_transactions`.`payment_transaction_type_id` = `gaming_payment_transaction_type`.`payment_transaction_type_id`)))
        LEFT JOIN `gaming_clients` ON ((`gaming_clients`.`client_id` = `gaming_balance_manual_transactions`.`client_id`)))
        LEFT JOIN `gaming_client_stats` ON ((`gaming_client_stats`.`client_id` = `gaming_clients`.`client_id`)))
        LEFT JOIN `gaming_operator_currency` ON ((`gaming_operator_currency`.`currency_id` = `gaming_client_stats`.`currency_id`)))
        LEFT JOIN `gaming_balance_accounts` ON ((`gaming_balance_accounts`.`balance_account_id` = `gaming_balance_manual_transactions`.`balance_account_id`)))
        LEFT JOIN `gaming_balance_history` FORCE INDEX (BALANCE_MANUAL_TRANSACTION_ID) ON ((`gaming_balance_history`.`balance_manual_transaction_id` = `gaming_balance_manual_transactions`.`balance_manual_transaction_id`)))
        LEFT JOIN `gaming_currency` ON ((`gaming_currency`.`currency_id` = `gaming_client_stats`.`currency_id`)))
        LEFT JOIN `history_gaming_operator_currency` `exrate` ON (((`exrate`.`operator_id` = 3)
            AND (`gaming_client_stats`.`currency_id` = `exrate`.`currency_id`)
            AND (`exrate`.`history_datetime_from` < `gaming_balance_manual_transactions`.`transaction_date`)
            AND (`exrate`.`history_datetime_to` > `gaming_balance_manual_transactions`.`transaction_date`))))
        LEFT JOIN `gaming_transaction_reconcilation_statuses` ON ((`gaming_transaction_reconcilation_statuses`.`transaction_reconcilation_status_id` = `gaming_balance_manual_transactions`.`transaction_reconcilation_status_id`)))
        LEFT JOIN `gaming_payment_transaction_status` ON ((`gaming_balance_history`.`payment_transaction_status_id` = `gaming_payment_transaction_status`.`payment_transaction_status_id`)))
        LEFT JOIN `gaming_payment_file_import_summary` ON ((`gaming_payment_file_import_summary`.`payment_file_import_summary_id` = `gaming_balance_manual_transactions`.`payment_file_import_summary_id`)))
        LEFT JOIN `gaming_balance_withdrawal_requests` ON ((`gaming_balance_withdrawal_requests`.`balance_history_id` = `gaming_balance_history`.`balance_history_id`)))
        LEFT JOIN `gaming_balance_request_creator_types` ON ((`gaming_balance_manual_transactions`.`request_creator_type_id` = `gaming_balance_request_creator_types`.`request_creator_type_id`)))
        LEFT JOIN `users_main` ON ((`gaming_balance_manual_transactions`.`request_creator_id` = `users_main`.`user_id`)))
    WHERE
        (`gaming_balance_manual_transactions`.`payment_transaction_type_id` IN (1 , 241, 245))
		
		$$

DELIMITER ;
