DROP procedure IF EXISTS `PlayerValidatePlayerFields`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerValidatePlayerFields`(clientID BIGINT, varTitle VARCHAR(10), firstName VARCHAR(80), middleName VARCHAR(80), lastName VARCHAR(80),
 secLastName VARCHAR(80), varGender CHAR(1), countryISO CHAR(2), currencyISO CHAR(3), languageISO CHAR(2), varDOB DATETIME, emailAddress VARCHAR(80), 
 mobilePhone VARCHAR(45), priTelephone VARCHAR(45), secTelephone VARCHAR(45), playerCard VARCHAR(80), OUT statusCode INT)
root:BEGIN

	DECLARE vClientID, vPlayerCard BIGINT DEFAULT -1;
	DECLARE vVarTitle VARCHAR(10);
	DECLARE vFirstName, vMiddleName, vLastName, vSecLastName,vEmailAddress VARCHAR(80);
	DECLARE vVarGender CHAR(1);
	DECLARE vCountryISO, vLanguageISO VARCHAR(2);
	DECLARE vCurrencyISO VARCHAR(3);
	DECLARE vVarDOB DATETIME;
	DECLARE vMobilePhone,vPriTelephone,vSecTelephone VARCHAR(45);

	SELECT gaming_clients.client_id,title, gaming_clients.name, middle_name, surname, sec_surname, gender, country_code, currency_code, language_code, dob,
		email, mob, pri_telephone, sec_telephone, playercard_cards_id
	INTO vClientID, vVarTitle, vFirstName, vMiddleName, vLastName, vSecLastName, vVarGender, vCountryISO, vCurrencyISO, vLanguageISO, vVarDOB, 
		vEmailAddress, vMobilePhone, vPriTelephone, vSecTelephone, vPlayerCard
	FROM gaming_clients
	JOIN gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id
	LEFT JOIN clients_locations ON clients_locations.client_id = gaming_clients.client_id
	LEFT JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
	LEFT JOIN gaming_currency ON gaming_client_stats.currency_id = gaming_currency.currency_id
	LEFT JOIN gaming_languages ON gaming_languages.language_id = gaming_clients.language_id
	LEFT JOIN gaming_playercard_cards ON gaming_playercard_cards.client_id = gaming_clients.client_id AND card_status=0
	WHERE gaming_clients.client_id = clientID;

	IF (vClientID = -1) THEN
		SET statusCode = 1;
		LEAVE root;
	END IF;
    
    SET varDOB = CONCAT(DATE(varDOB), ' 00:00:00');

	IF (
		(varTitle IS NULL || varTitle = vVarTitle) &&
		(firstName IS NULL || firstName = vFirstName) &&
		(middleName IS NULL || middleName = vMiddleName) &&
		(lastName IS NULL || lastName = vLastName) &&
		(secLastName IS NULL || secLastName = vSecLastName) &&
		(varGender IS NULL || varGender = vVarGender) &&
		(countryISO IS NULL || countryISO = vCountryISO) &&
		(currencyISO IS NULL || currencyISO = vCurrencyISO) &&
		(languageISO IS NULL || languageISO = vLanguageISO) &&
		(varDOB IS NULL || varDOB = vVarDOB) &&
		(emailAddress IS NULL || emailAddress = vEmailAddress) &&
		(mobilePhone IS NULL || mobilePhone = vMobilePhone) &&
		(priTelephone IS NULL || priTelephone = vPriTelephone) &&
		(secTelephone IS NULL || secTelephone = vSecTelephone) &&
		(playerCard IS NULL || playerCard = vPlayerCard) 
		) THEN
		SET statusCode = 0;
	ELSE
		SET statusCode = 2;
	END IF;
END$$

DELIMITER ;

