DROP procedure IF EXISTS `PlayerGetDetails`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetDetails`(clientID BIGINT)
BEGIN
  -- Added country, town, postcode 
  
  CALL PlayerGetDetailsGeneral(clientID, NULL, NULL, NULL, NULL, NULL, 1);
 
  SELECT gaming_client_payment_info.client_id, gaming_payment_method.payment_method_id, gaming_payment_method.name AS payment_method_name, gaming_payment_method.display_name AS payment_method, account_name, account_holder_name, gaming_payment_method.require_client_info, is_entered, is_validated, is_disabled
  FROM gaming_client_payment_info
  JOIN gaming_payment_method ON gaming_client_payment_info.payment_method_id=gaming_payment_method.payment_method_id
  WHERE gaming_client_payment_info.client_id=clientID; 
  
  SELECT attr_name, attr_value, can_edit, can_delete, can_view, attr_type 
  FROM gaming_client_attributes 
  WHERE client_id=clientID;

  SELECT devAcc.device_account_id, devAcc.uuid, devAcc.created_date, devAcc.mac_address, devAcc.brand_name, devAcc.model_type, devAcc.platform_type,
		devAcc.os_name, devAcc.os_version, devAcc.browser_name, devAcc.browser_version, devAcc.user_agent, clDevAcc.first_used_date, clDevAcc.last_used_date
	FROM gaming_device_accounts as devAcc
    JOIN gaming_clients_device_accounts as clDevAcc ON devAcc.device_account_id = clDevAcc.device_account_id 
  WHERE client_id=clientID;

  SELECT clients_phone_number_id,client_id,country_prefix_id,mobile_prefix_id,phone_number,phone_number_type,mobile_prefix,country_prefix
  FROM gaming_clients_phone_numbers
  WHERE client_id=clientID;
   
SELECT gaming_client_registrations.created_date, gaming_client_registration_types.registration_code , 
  ipaddress_v6, ipaddress_v4, ip_country.country_code AS ip_country_code, platform_type, gaming_channel_types.channel_type_id, 
  gaming_channel_types.channel_type, gaming_client_registrations.is_current
  FROM gaming_client_registrations 
  LEFT JOIN gaming_client_registration_types ON gaming_client_registration_types.client_registration_type_id = gaming_client_registrations.client_registration_type_id 
  LEFT JOIN gaming_platform_types ON gaming_client_registrations.platform_type_id = gaming_platform_types.platform_type_id 
  LEFT JOIN  gaming_channel_types on gaming_client_registrations.channel_type_id = gaming_channel_types.channel_type_id
  LEFT JOIN gaming_countries AS ip_country ON gaming_client_registrations.country_id_from_ip=ip_country.country_id
  WHERE gaming_client_registrations.client_id = clientID ORDER BY gaming_client_registrations.created_date DESC;

END$$

DELIMITER ;

