DROP function IF EXISTS `AuditLogAttributeChangeFunc`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `AuditLogAttributeChangeFunc`(attrName VARCHAR(255), subjectId BIGINT, logGroupId BIGINT, 
  newValue VARCHAR(1024), oldValue VARCHAR(1024), effectiveDate DATETIME) RETURNS INT(11)
BEGIN
	
    DECLARE changeNo INT DEFAULT 1; 
	    
	SELECT IFNULL(MAX(gaming_client_audit_logs.change_no), 1) +1 
    INTO changeNo 
	FROM gaming_client_audit_log_groups FORCE INDEX (subject_id)		
	STRAIGHT_JOIN gaming_client_audit_logs FORCE INDEX (client_audit_log_group_id) ON 
		gaming_client_audit_logs.client_audit_log_group_id = gaming_client_audit_log_groups.client_audit_log_group_id AND attr_name = attrName
	WHERE gaming_client_audit_log_groups.subject_id = subjectId  
    ORDER BY change_no DESC 
    LIMIT 1; 

	INSERT INTO gaming_client_audit_logs (client_audit_log_group_id, attr_name, attr_value, attr_value_before, effective_date, change_no)
	VALUES(logGroupId, attrName, newValue, oldValue, IFNULL(effectiveDate, NOW()), changeNo);
    
	RETURN 1;
    
END$$

DELIMITER ;

