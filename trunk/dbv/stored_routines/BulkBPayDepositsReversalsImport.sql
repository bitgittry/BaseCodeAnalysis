DROP procedure IF EXISTS `BulkBPayDepositsReversalsImport`;

DELIMITER $$
CREATE DEFINER=`root`@`127.0.0.1` PROCEDURE `BulkBPayDepositsReversalsImport`(listOfStagingIDs longtext)
BEGIN
	DECLARE vFinished integer DEFAULT 0; -- Check if cursor finished
	DECLARE vDeposit varchar(100) DEFAULT ""; -- Holds current row

	-- Variables Needed in loop
	DECLARE paymentMethodID long DEFAULT 271;
	DECLARE paymentMethod varchar(100) DEFAULT "BPay";
	DECLARE accountReference varchar(255) DEFAULT "";
	DECLARE activeOnly bool DEFAULT TRUE;
	DECLARE nonInternalOnly bool DEFAULT TRUE;

	DECLARE clientStatID long DEFAULT 0;
	DECLARE balanceAccountID long DEFAULT 0;
	-- DECLARE balanceAccountIDCount integer DEFAULT 0;
	DECLARE statusCode integer DEFAULT 0;

	-- Needed for manual deposit
	DECLARE transactionAmount long DEFAULT 0;
	DECLARE transactionSettlementDate DATETIME DEFAULT NULL;
	DECLARE transactionReferenceNumber varchar(255) DEFAULT "";
	DECLARE gateHeaderID integer DEFAULT 0;

	-- Matched Deposits
	DECLARE depoitsImportCursor CURSOR FOR
	SELECT
		gate_detail_id,
		IFNULL(staging_deposits.customer_reference_number, ""),
		IFNULL(staging_deposits.amount, ""),
		IFNULL(staging_deposits.transaction_reference_number, ""),
		settlement_date,
		IFNULL(staging_deposits.gate_header_id, "")
	FROM staging_gd_bpay_deposits_import staging_deposits
	WHERE FIND_IN_SET(staging_deposits.gate_detail_id, listOfStagingIDs)
	AND record_status = 1
	AND type_code = "399";
	

	-- declare NOT FOUND handler
	DECLARE CONTINUE HANDLER
	FOR NOT FOUND SET vFinished = 1;

	OPEN depoitsImportCursor;

	processDepoits: LOOP

		FETCH 
			depoitsImportCursor
		INTO
			vDeposit,
			accountReference,
			transactionAmount,
			transactionReferenceNumber,			
			transactionSettlementDate,
			gateHeaderID;

		IF vFinished = 1 THEN
			LEAVE processDepoits;
		END IF;

		-- Getting client_stat_id
		/* SELECT
			IFNULL(gba.client_stat_id, "") INTO clientStatID
		FROM gaming_balance_accounts gba
			JOIN gaming_balance_account_attributes gbaa
				ON gba.balance_account_id = gbaa.balance_account_id AND gbaa.attr_name = 'crn'
			JOIN staging_gd_bpay_deposits_import sgbdi
				ON gbaa.attr_value = sgbdi.customer_reference_number
		WHERE sgbdi.gate_detail_id = vDeposit
		AND gbaa.attr_value = sgbdi.customer_reference_number LIMIT 1;

		-- Getting balance_account_id
		SELECT
			gba.balance_account_id,
			COUNT(gba.balance_account_id) INTO balanceAccountID, balanceAccountIDCount
		FROM gaming_balance_account_attributes gbaa
			LEFT JOIN gaming_balance_accounts gba
			ON gba.balance_account_id = gbaa.balance_account_id
		WHERE gbaa.attr_value = accountReference AND gbaa.attr_name = 'crn';*/

		SELECT balance_account_id, client_stat_id INTO balanceAccountID, clientStatID FROM gaming_balance_accounts
		WHERE customer_reference_number = accountReference AND is_active = 1;

/*
		-- Creating Balance Account if not found
		IF balanceAccountIDCount = 0 THEN
			CALL TransactionBalanceAccountUpdate(NULL, clientStatID, accountReference, NULL, NULL, paymentMethodID, 1, 0, NULL, 0, 0, NULL, NULL, 0, 0, NULL, balanceAccountID, statusCode);
		END IF;*/

		-- Creaing a Manual Deposit
		CALL TransactionCreateManualDeposit(clientStatID, paymentMethodID, balanceAccountID, transactionAmount, NULL, transactionReferenceNumber, NULL, "Matched Deposit", CONCAT("BPay Import GateDetailID:", vDeposit), 0, 0, NULL, @out_var, "back-office", NULL, 0, statusCode, vDeposit, gateHeaderID, 1, "Match", "Accepted", transactionSettlementDate, 0, 1);

	END LOOP processDepoits;

	CLOSE depoitsImportCursor;

	-- Matched Reversals
	UPDATE gaming_balance_manual_transactions AS manual_transactions
	JOIN staging_gd_bpay_deposits_import AS staging_deposits
		ON staging_deposits.original_reference_number = manual_transactions.external_reference AND staging_deposits.original_reference_number != ''
	SET	transaction_reconcilation_status_id = 8, -- Reverse
		manual_transactions.reason = staging_deposits.reason,
		notes = 'Successfully reversed transaction from bank',
		manual_transactions.gate_detail_id = staging_deposits.gate_detail_id,
        manual_transactions.payment_file_import_summary_id = staging_deposits.gate_header_id
		-- manual_transactions.external_reference = staging_deposits.transaction_reference_number,
		-- manual_transactions.transaction_date = staging_deposits.date_of_payment,
		-- manual_transactions.processed_date = staging_deposits.settlement_date
	WHERE FIND_IN_SET(staging_deposits.gate_detail_id, listOfStagingIDs)
	AND staging_deposits.record_status = 1
	AND staging_deposits.type_code IN ("699");

	-- Unmatched Deposits and Reversals
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
			IFNULL(gcs.client_id, 0) AS client_id,
			IFNULL(gcs.client_stat_id, 0) AS client_stat_id,
			1 AS payment_transaction_type_id, -- Deposit
			271 AS payment_method_id,
			0 AS balance_account_id,
			sgbdi.amount AS amount,
			CASE type_code
				WHEN "399" THEN
					NOW()
				WHEN "699" THEN
					date_of_payment
			END AS transaction_date,
			transaction_reference_number AS external_reference,
			-- sgbdi.gate_detail_id AS reason,
			CASE type_code
				WHEN "399" THEN
					"Unmatch"
				WHEN "699" THEN
					sgbdi.reason			
			END AS reason,

			CASE type_code
				WHEN "399" THEN
					CASE sgbdi.record_status
						WHEN 2 THEN
							"Unmatched Deposit due to CRN mismatch"
					END
				WHEN "699" THEN
					CASE sgbdi.record_status
						WHEN 3 THEN
							CONCAT("Unsuccessful Reversal due to missing initial transaction. External Reference: ", sgbdi.transaction_reference_number)
						WHEN 4 THEN CONCAT("Unsuccessful Reversal due to missmatch amount. External Reference: ", sgbdi.transaction_reference_number)
					END
			END AS notes,
			0 AS user_id,
			0 AS session_id,
			NOW() AS created_date, 3 /* System type*/, 1 /* user_id of system */,
			0 AS is_cancelled,
			CASE type_code
				WHEN "399" THEN
					2 -- Unmatch
				WHEN "699" THEN
					8 -- Reverse 					
			END AS payment_reconciliation_status_id,
			sgbdi.gate_detail_id AS gate_detail_id,
			sgbdi.gate_header_id AS payment_file_import_summary_id,
			CASE type_code
				WHEN "399" THEN
					2 -- Unmatch
				WHEN "699" THEN
					8 -- Reverse 				
			END AS transaction_reconcilation_status_id,
			sgbdi.settlement_date
		FROM staging_gd_bpay_deposits_import sgbdi
		LEFT JOIN gaming_balance_accounts gba ON gba.customer_reference_number = sgbdi.customer_reference_number
		LEFT JOIN gaming_client_stats gcs ON gba.client_stat_id = gcs.client_stat_id
		WHERE FIND_IN_SET(sgbdi.gate_detail_id, listOfStagingIDs)
		AND record_status NOT IN (-1, 1)
		AND type_code in ("399", "699");

END$$

DELIMITER ;

