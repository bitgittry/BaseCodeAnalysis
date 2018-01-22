
DROP procedure IF EXISTS `FraudRuleGetAllSettingsByClientID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudRuleGetAllSettingsByClientID`(clientID BIGINT)
BEGIN
 
-- set the main setting data
SELECT *
FROM gaming_fraud_rule_client_settings
WHERE client_id = clientID;

-- get data for disable login
SELECT clientID AS client_id,  gaming_platform_types.platform_type_id, gaming_platform_types.platform_type AS 'name', IFNULL(settings.setting_value, 0) AS setting_value, 1 AS 'is_active'
FROM gaming_platform_types 
LEFT JOIN gaming_fraud_rule_disable_login_settings AS settings ON gaming_platform_types.platform_type_id = settings.platform_type_id AND settings.client_id = clientID;


-- get data for disable payment method group
SELECT clientID AS client_id, gaming_payment_method_groups.payment_method_group_id, gaming_payment_method_groups.display_name AS 'name', IFNULL(settings.setting_value, 0) AS setting_value, 1 AS 'is_active'
FROM gaming_payment_method_groups
LEFT JOIN gaming_fraud_rule_disable_pmgroup_settings AS settings ON gaming_payment_method_groups.payment_method_group_id = settings.payment_method_group_id
AND settings.client_id = clientID;


-- get data for disable payment method
SELECT clientID AS client_id, gaming_payment_method.payment_method_id, gaming_payment_method.display_name AS 'name', IFNULL(settings.setting_value, 0) AS setting_value, is_active AS 'is_active' 
FROM gaming_payment_method
LEFT JOIN  gaming_fraud_rule_disable_pm_settings AS settings ON gaming_payment_method.payment_method_id = settings.payment_method_id AND settings.client_id = clientID;
 

-- get data for disable promo
SELECT clientID AS client_id, gaming_communication_types.communication_type_id, gaming_communication_types.name AS 'name', IFNULL(settings.setting_value, 0) AS setting_value, 1 AS 'is_active'
FROM gaming_communication_types 
LEFT JOIN gaming_fraud_rule_disable_promo_settings AS settings ON settings.communication_type_id = gaming_communication_types.communication_type_id
AND settings.client_id = clientID;

-- get all not dynamic actions 
select * from gaming_fraud_rule_actions WHERE dynamic_action_type_id IS NULL;

END$$

DELIMITER ;

