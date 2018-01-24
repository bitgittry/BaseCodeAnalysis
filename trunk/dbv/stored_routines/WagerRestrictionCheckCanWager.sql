DROP function IF EXISTS `WagerRestrictionCheckCanWager`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `WagerRestrictionCheckCanWager`(licenceTypeID TINYINT(4), sessionID BIGINT) RETURNS tinyint(1)
BEGIN

  -- Optimized

	DECLARE countryIDFromIP, countryIDResidence BIGINT DEFAULT -1;
	DECLARE residenceNotAllowed, ipNotAllowed TINYINT(1);
	DECLARE allowedWager TINYINT(1) DEFAULT 1;
	
	-- Retrieve login Ip and residence of client
	SELECT IFNULL(sessions_main.country_id_from_ip, gaming_clients.country_id_from_ip), clients_locations.country_id
	INTO countryIDFromIP, countryIDResidence
	FROM sessions_main 
	STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id=sessions_main.extra_id
	STRAIGHT_JOIN clients_locations ON clients_locations.client_id=gaming_clients.client_id 
		AND clients_locations.is_primary AND clients_locations.is_active
	WHERE sessions_main.session_id = sessionID
	LIMIT 1;
 
    -- Check Country of Residence
	SELECT IF(gaming_license_type_country.residence_not_allowed, 0, 1)
	INTO allowedWager
	FROM gaming_license_type_country
	WHERE gaming_license_type_country.license_type_id = licenceTypeID AND gaming_license_type_country.country_id = countryIDResidence;

    -- Check country from IP
    IF (allowedWager=1) THEN
		SELECT IF(ip_not_allowed, 0, 1) 
		INTO allowedWager
		FROM gaming_license_type_country
		WHERE license_type_id = licenceTypeID AND gaming_license_type_country.country_id = countryIDFromIP;
    END IF;

    RETURN allowedWager;
END$$

DELIMITER ;

