DROP procedure IF EXISTS `CountryGetCoutnryFieldDefinitions`;
DROP procedure IF EXISTS `CountryGetCountryFieldDefinitions`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CountryGetCountryFieldDefinitions` (countryID BIGINT, countryCode CHAR(2), countryName VARCHAR(80))
BEGIN
	DECLARE selectedCountry BIGINT;

	SELECT country_id 
	INTO selectedCountry
	FROM gaming_countries
	WHERE country_id=countryID OR country_code=countryCode OR `name`=countryName;

	SELECT selectedCountry AS country_id, cfdt.countries_field_definition_type_id, IFNULL(cfd.countries_field_definitions_id, -1) AS countries_field_definitions_id, 
	   cfdt.countries_field_type_description, IFNULL(cfd.is_visible,1) AS is_visible,
		CASE 
			WHEN is_mandatory IS NULL AND cfdt.countries_field_definition_type_id = 1 THEN 1
			WHEN is_mandatory IS NULL THEN 0
			ELSE is_mandatory
		END AS is_mandatory,
		CASE 
			WHEN is_restricted_to_list IS NULL AND cfdt.countries_field_definition_type_id IN(6,7,8,10) THEN -1
			WHEN is_restricted_to_list IS NULL THEN 0
			ELSE is_restricted_to_list
		END AS is_restricted_to_list
	FROM gaming_countries_field_definition_types cfdt
	LEFT JOIN gaming_countries_field_definitions cfd ON cfd.countries_field_definition_type_id = cfdt.countries_field_definition_type_id AND cfd.country_id = selectedCountry
	WHERE cfdt.is_enabled=1;
END$$

DELIMITER ;

