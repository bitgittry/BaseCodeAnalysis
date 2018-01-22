DROP procedure IF EXISTS `PaymentsValidateAndUploadFile`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PaymentsValidateAndUploadFile`(batchjournalID BIGINT, OUT statusCode INT)
root: BEGIN

	DECLARE fileHitCount INT DEFAULT 0;

	SELECT COUNT(*) INTO fileHitCount
	FROM gaming_payments_file_repository
	JOIN gaming_payments_file_repository AS already_inserted ON  already_inserted.batch_journal_id = batchjournalID
	WHERE gaming_payments_file_repository.file_name = already_inserted.file_name;
    
    IF (fileHitCount > 1) THEN
		SET statusCode =1;
        LEAVE root;
    END IF;

	SELECT file_data, file_size, file_type_separator
	FROM gaming_payments_file_repository
	JOIN gaming_batch_action_journal ON gaming_batch_action_journal.batch_journal_id = gaming_payments_file_repository.batch_journal_id
	JOIN gaming_payment_file_types ON gaming_payment_file_types.file_type_id = gaming_batch_action_journal.file_type_id
	WHERE gaming_payments_file_repository.batch_journal_id = batchjournalID;
    
    SET statusCode = 0;


END$$

DELIMITER ;

