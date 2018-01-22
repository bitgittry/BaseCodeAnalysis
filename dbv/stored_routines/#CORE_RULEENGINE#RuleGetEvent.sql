DROP procedure IF EXISTS `RuleGetEvent`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleGetEvent`(eventId BIGINT)
BEGIN
	    SELECT event_id,gaming_event_types.name AS 'event_type',gaming_events.name AS 'event_name',
      description,priority, is_continous
      FROM gaming_events
      JOIN gaming_event_types ON gaming_events.event_type_id = gaming_event_types.event_type_id
      WHERE event_id=eventId;
      
      SELECT gaming_events_vars.event_var_id,var_reference,name,default_value, enum_values, is_currency, non_editable FROM gaming_events_vars
      JOIN gaming_events_var_types ON gaming_events_var_types.event_var_type_id=gaming_events_vars.event_var_type_id
      WHERE event_id=eventId;
      
END$$

DELIMITER ;