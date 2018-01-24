DROP procedure IF EXISTS `PlayerSelectionGetPlayersInSelection`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionGetPlayersInSelection`(playerSelectionID BIGINT, topN INT)
BEGIN
  
  -- Optimized
  -- Added password policy fields 
   -- Added country, town, postcode
  
  SELECT  
        gaming_clients.client_id, gaming_clients.last_updated, gaming_client_stats.client_stat_id, gaming_clients.title, gaming_clients.name, gaming_clients.middle_name, gaming_clients.surname, gaming_clients.sec_surname, gender, address_1, address_2, 
    gaming_countries.country_code, gaming_countries.country_code_alpha3, currency_code, language_code, gaming_clients.dob, gaming_clients.email, gaming_clients.mob, gaming_clients.pri_telephone, gaming_clients.sec_telephone, username, salt, nickname, PIN1, 
    receive_promotional_by_email, receive_promotional_by_sms, receive_promotional_by_post, receive_promotional_by_phone, receive_promotional_by_mobile, receive_promotional_by_third_party, 
	gaming_clients.email_verification_type_id, gaming_clients.sms_verification_type_id, gaming_clients.post_verification_type_id, gaming_clients.phone_verification_type_id, gaming_clients.third_party_verification_type_id, gaming_clients.preferred_promotion_type_id,
	gaming_clients.contact_by_email, gaming_clients.contact_by_sms, gaming_clients.contact_by_post, gaming_clients.contact_by_phone, gaming_clients.contact_by_mobile, gaming_clients.contact_by_third_party, 
	gaming_clients.sign_up_date, first_deposit_date, client_segment_id, risk_client_segment_id, allow_login_banned_country_ip,
    gaming_affiliates.affiliate_id, gaming_affiliates.affiliate_code, gaming_affiliate_coupons.coupon_code AS affiliate_coupon_code, gaming_bonus_coupons.coupon_code AS bonus_coupon_code, 
    gaming_clients.is_active, (gaming_clients.is_account_closed OR IFNULL(gaming_fraud_rule_client_settings.block_account, 0)) AS is_account_closed, gaming_clients.is_suspicious, gaming_clients.is_test_player, is_affiliate, gaming_clients.is_kyc_checked, gaming_clients.notes, gaming_clients.referral_code,
    gaming_clients.affiliate_registration_code, gaming_clients.original_affiliate_coupon_code, gaming_clients.original_bonus_coupon_code, gaming_affiliate_systems.name AS affiliate_system_name, gaming_clients.original_referral_code,
    gaming_clients.is_play_allowed, gaming_clients.test_player_allow_transfers, gaming_clients.account_activated, gaming_clients.activation_code, gaming_client_acquisition_types.display_name AS acquisition_type,ext_client_id, referral_client_id,
    gaming_clients.registration_ipaddress AS ip_address_v6, gaming_clients.registration_ipaddress_v4 AS ip_address_v4, ip_country.country_code AS ip_country_code, 
    gaming_clients.exceeded_login_attempts, gaming_clients.vip_level, IF(gaming_clients.bonus_seeker OR IFNULL(gaming_fraud_rule_client_settings.bonus_seeker, 0),1,0) AS bonus_seeker, gaming_clients.bonus_dont_want, gaming_clients.risk_score, gaming_clients.deposit_allowed, gaming_clients.withdrawal_allowed,
	gaming_clients.mac_address, gaming_clients.download_client_id, gaming_clients.rnd_score, gaming_platform_types.platform_type, gaming_clients.news_feeds_allow,
	bet_factor, age_verification_types.name AS age_verification_type_name, gaming_clients.age_verification_date, 
	gaming_clients.account_closed_level, gaming_countries.eMarsys_country_id,  gaming_languages.eMarsys_language_id, gaming_clients.vip_level_id, 
    gaming_vip_levels.name AS vip_level_name, gaming_affiliates.external_id AS ext_affiliate_id,
	gaming_clients.last_password_change_date, gaming_clients.num_password_changes, gaming_clients.vip_downgrade_disabled, 
    gaming_client_stats.loyalty_points_running_total, gaming_client_stats.loyalty_points_reset_date, 
    gaming_clients.day_of_year_dob, gaming_clients.day_of_year_sign_up, gaming_clients.num_details_changes, 
    gaming_client_registration_types.registration_code AS registrationType,
	clients_locations.country_id, clients_locations.city_id, IFNULL(clients_locations.city, country_city.countries_municipality_name) AS city, 
    clients_locations.state_id AS country_state_id, IFNULL(clients_locations.state_name, gaming_countries_states.name) AS country_state_name, 
    IFNULL(clients_locations.town_name, country_town.countries_municipality_name) AS town_name, clients_locations.town_id, 
    clients_locations.postcode_id, IFNULL(clients_locations.postcode, gaming_countries_post_codes.country_post_code_name) AS postcode, 
    IFNULL(clients_locations.street_type_id, gaming_countries_street_types.street_type_id) AS street_type_id, 
    IFNULL(clients_locations.street_type_desc, gaming_countries_street_types.street_type_description) AS street_type_desc, 
    IFNULL(clients_locations.street_name, gaming_countries_streets.countries_street_description) AS street_name, clients_locations.street_id, 
    clients_locations.street_number, clients_locations.house_name, clients_locations.house_number, clients_locations.flat_number, clients_locations.po_box_name, 
    IFNULL(clients_locations.suburb, gaming_countries_suburbs.suburb_name) AS suburb, clients_locations.suburb_id,
    gaming_client_stats.max_player_balance_threshold, gaming_player_statuses.player_status_name, gaming_kyc_checked_statuses.status_name AS kyc_checked_status_name, 
    gaming_kyc_checked_statuses.kyc_checked_status_id, gaming_kyc_checked_statuses.display_name as kyc_checked_status_display_name, gaming_clients.kyc_checked_date AS kyc_checked_date,
    gaming_kyc_checked_statuses.status_code, PadPlayerCard(gaming_playercard_cards.playercard_cards_id) AS playercard_id, last_dormant_date, is_dormant_account, closure_review_date
   FROM gaming_player_selections_player_cache AS CS 
   STRAIGHT_JOIN gaming_client_stats ON CS.client_stat_id=gaming_client_stats.client_stat_id AND gaming_client_stats.is_active=1
   STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id=gaming_client_stats.client_id  
   STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id = gaming_client_stats.currency_id 
   STRAIGHT_JOIN gaming_client_registrations ON gaming_client_registrations.client_id = gaming_clients.client_id AND is_current=1
   STRAIGHT_JOIN gaming_client_registration_types ON gaming_client_registration_types.client_registration_type_id = gaming_client_registrations.client_registration_type_id 
  LEFT JOIN gaming_languages ON gaming_clients.language_id = gaming_languages.language_id 
  LEFT JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id AND clients_locations.is_primary=1 
  LEFT JOIN gaming_countries_streets ON gaming_countries_streets.countries_street_id=clients_locations.street_id
  LEFT JOIN gaming_countries_street_types ON gaming_countries_street_types.street_type_id=gaming_countries_streets.street_type_id
  LEFT JOIN gaming_countries_suburbs ON gaming_countries_suburbs.suburb_id=clients_locations.suburb_id
  LEFT JOIN gaming_countries_post_codes ON gaming_countries_post_codes.countries_post_code_id=clients_locations.postcode_id
  LEFT JOIN gaming_countries_municipalities AS country_town ON country_town.countries_municipality_id=clients_locations.town_id AND country_town.municipality_type_id=2 -- 'Town' 
  LEFT JOIN gaming_countries_municipalities AS country_city ON country_city.countries_municipality_id=clients_locations.city_id AND country_city.municipality_type_id=1 -- 'City'
  LEFT JOIN gaming_countries_states ON gaming_countries_states.state_id=clients_locations.state_id
  LEFT JOIN gaming_countries ON clients_locations.country_id = gaming_countries.country_id 
  LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
  LEFT JOIN gaming_affiliate_coupons ON gaming_clients.affiliate_coupon_id=gaming_affiliate_coupons.affiliate_coupon_id
  LEFT JOIN gaming_bonus_coupons ON gaming_clients.bonus_coupon_id=gaming_bonus_coupons.bonus_coupon_id
  LEFT JOIN gaming_affiliate_systems ON gaming_clients.affiliate_system_id=gaming_affiliate_systems.affiliate_system_id 
  LEFT JOIN gaming_client_acquisition_types ON gaming_clients.client_acquisition_type_id=gaming_client_acquisition_types.client_acquisition_type_id          
  LEFT JOIN gaming_countries AS ip_country ON gaming_clients.country_id_from_ip=ip_country.country_id
  LEFT JOIN gaming_platform_types ON gaming_clients.platform_type_id=gaming_platform_types.platform_type_id
  LEFT JOIN gaming_client_age_verification_types AS age_verification_types ON age_verification_types.client_age_verification_type_id=gaming_clients.age_verification_type_id
  LEFT JOIN gaming_vip_levels ON gaming_clients.vip_level_id=gaming_vip_levels.vip_level_id 
  LEFT JOIN gaming_player_statuses ON gaming_clients.player_status_id = gaming_player_statuses.player_status_id
  LEFT JOIN gaming_kyc_checked_statuses ON gaming_clients.kyc_checked_status_id = gaming_kyc_checked_statuses.kyc_checked_status_id  
  LEFT JOIN gaming_playercard_cards ON gaming_playercard_cards.client_id = gaming_clients.client_id AND card_status=0
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
  WHERE (CS.player_selection_id=playerSelectionID AND CS.player_in_selection=1) AND (gaming_clients.is_account_closed=0 AND IFNULL(gaming_fraud_rule_client_settings.block_account,0) = 0)
  ORDER BY CS.client_stat_id DESC
  LIMIT topN;

END$$

DELIMITER ;

