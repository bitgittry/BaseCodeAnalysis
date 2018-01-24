DROP procedure IF EXISTS `RuleGetModuleData`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetModuleData`()
BEGIN

  SELECT license_type_id,name FROM gaming_license_type WHERE is_active=1;

  SELECT event_type_id,name,display_name FROM gaming_event_types;
  
  SELECT query_date_interval_type_id,name FROM gaming_query_date_interval_types WHERE is_rule_interval=1;
	
END$$

DELIMITER ;
