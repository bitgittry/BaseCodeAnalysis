DROP procedure IF EXISTS `ClientGetCompiledAddress`;
DROP function IF EXISTS `ClientGetCompiledAddress`;

DELIMITER $$
CREATE DEFINER=`root`@`localhost` FUNCTION `ClientGetCompiledAddress`(clientID BIGINT, addressDelimiter CHAR(1)) RETURNS varchar(1024) CHARSET utf8
BEGIN

  DECLARE addressFormat, addressItem, addressItemDescription, compiledAddress NVARCHAR(1024);
  DECLARE tempDelimiter CHAR(1);

  DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE clientLocationID, addressIndex BIGINT DEFAULT -1;

  SET compiledAddress = '';
  SET tempDelimiter = '';

  SELECT l.client_location_id, d.address_format INTO clientLocationID, addressFormat FROM clients_locations l JOIN gaming_countries d ON d.country_id = l.country_id WHERE client_id=clientID;
  IF(addressFormat IS NULL OR addressFormat = '') THEN
    RETURN compiledAddress;
  END IF;

  SET addressIndex = 1;

  SELECT SPLIT_STR(addressFormat, ',', addressIndex) INTO addressItem;
  WHILE (addressItem IS NOT NULL AND addressItem <> '') DO

    CASE addressItem
      WHEN 1 THEN 
	    SELECT gaming_countries.name INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries ON gaming_countries.country_id=clients_locations.country_id
        WHERE client_location_id=clientLocationID;

      WHEN 2 THEN 
	    SELECT IFNULL(clients_locations.state_name, gaming_countries_states.name) INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries_states ON gaming_countries_states.state_id=clients_locations.state_id
        WHERE client_location_id=clientLocationID;

      WHEN 3 THEN 
	    SELECT IFNULL(clients_locations.city, country_city.countries_municipality_name) INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries_municipalities AS country_city ON country_city.countries_municipality_id=clients_locations.town_id AND country_city.municipality_type_id=2
        WHERE client_location_id=clientLocationID;

      WHEN 4 THEN 
	    SELECT IFNULL(clients_locations.street_type_desc, gaming_countries_street_types.street_type_description) INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries_street_types ON gaming_countries_street_types.street_type_id=clients_locations.street_type_id
        WHERE client_location_id=clientLocationID;

      WHEN 5 THEN 
	    SELECT IFNULL(clients_locations.street_name, gaming_countries_streets.countries_street_description) INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries_streets ON gaming_countries_streets.countries_street_id=clients_locations.street_id
        WHERE client_location_id=clientLocationID;

      WHEN 6 THEN 
	    SELECT house_name INTO @result 
        FROM clients_locations
        WHERE client_location_id=clientLocationID;

      WHEN 7 THEN 
	    SELECT house_number INTO @result 
        FROM clients_locations
        WHERE client_location_id=clientLocationID;

      WHEN 8 THEN 
	    SELECT flat_number INTO @result 
        FROM clients_locations
        WHERE client_location_id=clientLocationID;

      WHEN 10 THEN 
	    SELECT po_box_name INTO @result 
        FROM clients_locations
        WHERE client_location_id=clientLocationID;

      WHEN 11 THEN 
	    SELECT IFNULL(clients_locations.postcode, gaming_countries_post_codes.country_post_code_name) INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries_post_codes ON gaming_countries_post_codes.countries_post_code_id=clients_locations.postcode_id
        WHERE client_location_id=clientLocationID;

      WHEN 12 THEN 
	    SELECT IFNULL(clients_locations.suburb, gaming_countries_suburbs.suburb_name) INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries_suburbs ON gaming_countries_suburbs.suburb_id=clients_locations.suburb_id
        WHERE client_location_id=clientLocationID;

      WHEN 14 THEN 
	    SELECT IFNULL(clients_locations.town_name, country_town.countries_municipality_name) INTO @result 
        FROM clients_locations
        LEFT JOIN gaming_countries_municipalities AS country_town ON country_town.countries_municipality_id=clients_locations.town_id AND country_town.municipality_type_id=2
        WHERE client_location_id=clientLocationID;

      WHEN 15 THEN 
	    SELECT street_number INTO @result 
        FROM clients_locations
        WHERE client_location_id=clientLocationID;

      ELSE
        SET @result = '';
    END CASE;

    IF(@result IS NOT NULL AND @result <> '') THEN
      SET compiledAddress = CONCAT(compiledAddress, tempDelimiter, @result);
      SET tempDelimiter = addressDelimiter;
    END IF;
    SET addressIndex = addressIndex + 1;
    SELECT SPLIT_STR(addressFormat, ',', addressIndex) INTO addressItem;
  END WHILE;

  RETURN compiledAddress;
END$$

DELIMITER ;

