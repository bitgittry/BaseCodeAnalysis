DROP procedure IF EXISTS `BulkBPointDepositsReversalsImport`;

DELIMITER $$
CREATE DEFINER=`root`@`127.0.0.1` PROCEDURE `BulkBPointDepositsReversalsImport`(listOfStagingIDs longtext)
BEGIN
	DECLARE vFinished integer DEFAULT 0; -- Check if cursor finished
	DECLARE vDeposit varchar(100) DEFAULT ""; -- Holds current row
    
	-- Variables Needed in loop
	DECLARE paymentMethodID long DEFAULT 272; -- BPoint
	DECLARE platformTypeID INT DEFAULT 6; -- back-office

	-- Matched Deposits
	UPDATE gaming_balance_manual_transactions
		JOIN gaming_balance_history ON gaming_balance_history.balance_manual_transaction_id = gaming_balance_manual_transactions.balance_manual_transaction_id
		JOIN staging_gd_bpoint_reconciliation_deposits_import AS staging_deposits ON staging_deposits.receipt_number = gaming_balance_history.payment_gateway_transaction_key
		SET	transaction_reconcilation_status_id = 1, -- Match
		gaming_balance_manual_transactions.gate_detail_id = staging_deposits.gate_detail_id,
        gaming_balance_manual_transactions.payment_file_import_summary_id = staging_deposits.gate_header_id,
		gaming_balance_manual_transactions.processed_date = gaming_balance_manual_transactions.transaction_date,
        gaming_balance_manual_transactions.transaction_date = staging_deposits.transaction_date
	WHERE FIND_IN_SET(staging_deposits.gate_detail_id, listOfStagingIDs) 
	AND staging_deposits.record_status = 1
	AND record_type = '50';
	
	-- Matched Deposit Reversals
	INSERT INTO gaming_balance_manual_transactions (client_id,
	client_stat_id,
	payment_transaction_type_id,
	payment_method_id,
	balance_account_id,
	amount,
	transaction_date,
	external_reference,
	reason,
	notes,
	user_id,
	session_id,
	created_date, request_creator_type_id, request_creator_id,
	is_cancelled,
	payment_reconciliation_status_id,
	gate_detail_id,
	payment_file_import_summary_id,
	transaction_reconcilation_status_id,
	processed_date)
		SELECT
			IFNULL(gaming_client_stats.client_id, 0) AS client_id,
			IFNULL(gaming_client_stats.client_stat_id, 0) AS client_stat_id,
			1 AS payment_transaction_type_id, -- Deposit
			272 AS payment_method_id, -- BPoint
			0 AS balance_account_id,
			amount_paid AS amount,
		    staging_deposits.transaction_date, -- NOW(),-- transaction_date AS transaction_date,
			receipt_number AS external_reference,	
			'Refund' AS reason,
			"" AS notes,
			0 AS user_id,
			0 AS session_id,
			NOW() AS created_date, 3 /* System type*/, 1 /* user_id of system */,
			0 AS is_cancelled,
			8 AS payment_reconciliation_status_id, -- Reverse
			staging_deposits.gate_detail_id AS gate_detail_id,
			gate_header_id AS payment_file_import_summary_id,
			8 AS transaction_reconcilation_status_id, -- Reverse
			NOW() -- transaction_date AS transaction_date -- NOW() 
		FROM staging_gd_bpoint_reconciliation_deposits_import staging_deposits
		LEFT JOIN gaming_clients ON gaming_clients.client_id = staging_deposits.customer_reference_number
        LEFT JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id AND gaming_client_stats.is_active = 1
		WHERE record_type in ('60')
		AND record_status = 1
		AND FIND_IN_SET(staging_deposits.gate_detail_id, listOfStagingIDs);

	-- Unmatched Deposits and Unmatched Deposit Reversals
	INSERT INTO gaming_balance_manual_transactions (client_id,
	client_stat_id,
	payment_transaction_type_id,
	payment_method_id,
	balance_account_id,
	amount,
	transaction_date,
	external_reference,
	reason,
	notes,
	user_id,
	session_id,
	created_date, request_creator_type_id, request_creator_id,
	is_cancelled,
	payment_reconciliation_status_id,
	gate_detail_id,
	payment_file_import_summary_id,
	transaction_reconcilation_status_id,
	processed_date)
		SELECT
			IFNULL(gaming_client_stats.client_id, 0) AS client_id,
			IFNULL(gaming_client_stats.client_stat_id, 0) AS client_stat_id,
			1 AS payment_transaction_type_id, -- Deposit
			272 AS payment_method_id, -- BPoint
			0 AS balance_account_id,
			staging_deposits.amount_paid AS amount,
			staging_deposits.transaction_date, -- NOW(), -- IFNULL(gaming_balance_manual_transactions.transaction_date, staging_deposits.transaction_date) AS transaction_date,
			staging_deposits.receipt_number AS external_reference,	
			CONCAT('Not matching receipt number ', staging_deposits.receipt_number, ', player ID#', staging_deposits.customer_reference_number) AS reason,
			CASE staging_deposits.record_status
				WHEN 2 THEN
							'Unmatched Deposit due to Player mismatch'
				ELSE
					CASE staging_deposits.record_type
						WHEN '50' THEN
							CASE staging_deposits.record_status
								WHEN 3 THEN 'Unmatched Deposit due to Initial Missing Transaction'
								WHEN 4 THEN 'Unmatched Deposit due to Amount Mismatch'
							END
					END
			END AS notes,
			0 AS user_id,
			0 AS session_id,
			NOW() AS created_date, 3 /* System type*/, 1 /* user_id of system */,
			0 AS is_cancelled,
			CASE staging_deposits.record_type
				WHEN '50' THEN
					2 -- Unmatch
				WHEN '60' THEN
					2 -- Reverse 	
			END AS payment_reconciliation_status_id,
			staging_deposits.gate_detail_id AS gate_detail_id,
			staging_deposits.gate_header_id AS payment_file_import_summary_id,
			CASE staging_deposits.record_type
				WHEN '50' THEN
					2 -- Unmatch
				WHEN '60' THEN
					2 -- Reverse 	
			END AS transaction_reconcilation_status_id, -- UnMatched
			NOW() -- IFNULL(gaming_balance_manual_transactions.transaction_date, staging_deposits.transaction_date) AS transaction_date -- staging_deposits.transaction_date
		FROM staging_gd_bpoint_reconciliation_deposits_import staging_deposits
		LEFT JOIN gaming_clients ON gaming_clients.client_id = staging_deposits.customer_reference_number
        LEFT JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id AND gaming_client_stats.is_active = 1
		LEFT JOIN gaming_balance_manual_transactions ON gaming_balance_manual_transactions.external_reference = staging_deposits.receipt_number
		WHERE record_status NOT IN (-1, 1)
		AND FIND_IN_SET(staging_deposits.gate_detail_id, listOfStagingIDs);
		
UPDATE staging_gd_bpoint_reconciliation_deposits_import staging_deposits SET is_processed = 1 WHERE FIND_IN_SET(staging_deposits.gate_detail_id, listOfStagingIDs);

END$$

DELIMITER ;

