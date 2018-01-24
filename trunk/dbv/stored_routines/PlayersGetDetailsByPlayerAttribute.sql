DROP procedure IF EXISTS `PlayersGetDetailsByPlayerAttribute`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayersGetDetailsByPlayerAttribute`(attributeName varchar(80), attributeValue varchar(255), activeOnly TINYINT(1))
BEGIN  
  SELECT 
		gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.title, gaming_clients.name, gaming_clients.middle_name, gaming_clients.surname, gaming_clients.sec_surname, gender, address_1, address_2, postcode, 
		city, country_code, currency_code, language_code, gaming_clients.dob,receive_promotional_by_mobile, gaming_clients.email, gaming_clients.mob, gaming_clients.pri_telephone, gaming_clients.sec_telephone, username, salt, nickname, PIN1, 
		receive_promotional_by_email, receive_promotional_by_sms, receive_promotional_by_post, receive_promotional_by_phone, receive_promotional_by_third_party, 
		gaming_clients.email_verification_type_id, gaming_clients.sms_verification_type_id, gaming_clients.post_verification_type_id, gaming_clients.phone_verification_type_id, gaming_clients.third_party_verification_type_id, gaming_clients.preferred_promotion_type_id, 
		gaming_clients.contact_by_email, gaming_clients.contact_by_sms, gaming_clients.contact_by_post, gaming_clients.contact_by_phone, gaming_clients.contact_by_third_party, 
		gaming_clients.sign_up_date, first_deposit_date, client_segment_id, allow_login_banned_country_ip,
		gaming_affiliates.affiliate_id, gaming_affiliates.affiliate_code, gaming_affiliate_coupons.coupon_code AS affiliate_coupon_code, gaming_bonus_coupons.coupon_code AS bonus_coupon_code, 
		gaming_clients.is_active, gaming_clients.is_account_closed, gaming_clients.is_suspicious, gaming_clients.is_test_player, gaming_clients.is_affiliate, gaming_clients.is_kyc_checked, gaming_clients.notes, gaming_clients.referral_code,
		gaming_clients.affiliate_registration_code, gaming_clients.original_affiliate_coupon_code, gaming_clients.original_bonus_coupon_code, gaming_affiliate_systems.name AS affiliate_system_name, gaming_clients.original_referral_code,
		gaming_clients.is_play_allowed, gaming_clients.test_player_allow_transfers, gaming_clients.account_activated, gaming_clients.activation_code, gaming_client_acquisition_types.name AS acquisition_type,ext_client_id, referral_client_id, 
		gaming_clients.exceeded_login_attempts, gaming_clients.bonus_seeker, gaming_clients.bonus_dont_want, gaming_clients.vip_level, gaming_clients.risk_score, gaming_clients.deposit_allowed, gaming_clients.withdrawal_allowed, gaming_clients.rnd_score, 
		clients_locations.state_id AS country_state_id, clients_locations.state_name AS country_state_name, clients_locations.town_name, clients_locations.town_id, age_verification_types.name AS age_verification_type_name, gaming_clients.age_verification_date, gaming_clients.vip_level_id, gaming_vip_levels.name AS vip_level_name,
		gaming_clients.last_password_change_date, gaming_clients.num_password_changes, gaming_clients.day_of_year_dob, gaming_clients.day_of_year_sign_up, gaming_clients.num_details_changes, gaming_client_registration_types.registration_code AS registrationType,
		clients_locations.country_id, clients_locations.city_id, clients_locations.postcode_id, clients_locations.street_type_desc, clients_locations.street_type_id, clients_locations.street_name, clients_locations.street_id, clients_locations.street_number, clients_locations.house_name, clients_locations.house_number, clients_locations.flat_number, clients_locations.po_box_name,
		clients_locations.suburb, clients_locations.suburb_id, gaming_client_stats.max_player_balance_threshold, gaming_player_statuses.player_status_name, gaming_kyc_checked_statuses.status_name AS kyc_checked_status_name, gaming_kyc_checked_statuses.kyc_checked_status_id, gaming_kyc_checked_statuses.display_name as kyc_checked_status_display_name, gaming_kyc_checked_statuses.status_code, gaming_clients.kyc_checked_date AS kyc_checked_date, 
    last_dormant_date, is_dormant_account, closure_review_date
	FROM gaming_client_stats FORCE INDEX (last_played_date)  
	STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id AND gaming_client_stats.is_active=1 
	STRAIGHT_JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
	STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id = gaming_client_stats.currency_id 
	STRAIGHT_JOIN gaming_client_registrations ON gaming_client_registrations.client_id = gaming_clients.client_id AND gaming_client_registrations.is_current = 1
	STRAIGHT_JOIN gaming_client_registration_types ON gaming_client_registration_types.client_registration_type_id = gaming_client_registrations.client_registration_type_id AND gaming_client_registration_types.registration_code != 'Anon'
	LEFT JOIN gaming_languages ON gaming_clients.language_id = gaming_languages.language_id 
	LEFT JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id AND clients_locations.is_primary=1 
	LEFT JOIN gaming_countries ON clients_locations.country_id = gaming_countries.country_id 
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
	LEFT JOIN gaming_affiliate_coupons ON gaming_clients.affiliate_coupon_id=gaming_affiliate_coupons.affiliate_coupon_id
	LEFT JOIN gaming_bonus_coupons ON gaming_clients.bonus_coupon_id=gaming_bonus_coupons.bonus_coupon_id
	LEFT JOIN gaming_affiliate_systems ON gaming_clients.affiliate_system_id=gaming_affiliate_systems.affiliate_system_id 
	LEFT JOIN gaming_client_acquisition_types ON gaming_clients.client_acquisition_type_id=gaming_client_acquisition_types.client_acquisition_type_id 
	LEFT JOIN gaming_client_age_verification_types AS age_verification_types ON age_verification_types.client_age_verification_type_id=gaming_clients.age_verification_type_id 
	LEFT JOIN gaming_kyc_checked_statuses ON gaming_clients.kyc_checked_status_id = gaming_kyc_checked_statuses.kyc_checked_status_id
	LEFT JOIN gaming_player_statuses ON gaming_clients.player_status_id = gaming_player_statuses.player_status_id
	LEFT JOIN gaming_vip_levels ON gaming_clients.vip_level_id=gaming_vip_levels.vip_level_id
	STRAIGHT_JOIN gaming_client_attributes ON gaming_clients.client_id = gaming_client_attributes.client_id
	WHERE 
		gaming_fraud_rule_client_settings.block_account = 0 
		AND gaming_clients.is_account_closed = 0 
		AND ((NOT activeOnly) OR (gaming_clients.is_active AND gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay))
		AND gaming_client_registrations.is_current = 1
		AND (gaming_client_attributes.attr_name = attributeName AND gaming_client_attributes.attr_value = attributeValue)
	LIMIT 100;
END$$

DELIMITER ;

