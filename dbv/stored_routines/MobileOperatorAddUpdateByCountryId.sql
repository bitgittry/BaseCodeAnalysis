DROP procedure IF EXISTS `MobileOperatorAddUpdateByCountryId`;

DELIMITER $$
CREATE PROCEDURE `MobileOperatorAddUpdateByCountryId` (countryID BIGINT, OUT operatorID BIGINT)
BEGIN
	DECLARE existingOperatorID BIGINT;

	SELECT countries_mobile_operator_id INTO existingOperatorID
	FROM gaming_countries_mobile_operators
	WHERE country_id = countryID;
	
	IF(isnull(existingOperatorID)) THEN
		INSERT INTO gaming_countries_mobile_operators(country_id,countries_mobile_operator_description,is_active)
		VALUES (countryID,'Automated Operator',1);

		SELECT LAST_INSERT_ID() INTO existingOperatorID;
	END IF;


	SET operatorID = existingOperatorID;
END$$

DELIMITER ;

