
DROP procedure IF EXISTS `TaxCalculateTax`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TaxCalculateTax`(licenseTypeID INT, clientStatID BIGINT, clientID BIGINT, winAmount DECIMAL(18,5), betAmount DECIMAL(18,5), OUT taxAmount DECIMAL(18,5), OUT appliedOn VARCHAR(20), OUT taxCycleID BIGINT)
BEGIN
/*
	- this SP calculates the tax amount of a win amount but only if the taxation is enabled.
	- check if taxation is enabled in the platform.  (setting TAX_ON_GAMEPLAY_ENABLED)
	- check if taxation is enabled for the vertical (casino, sportsbook, etc)
	- check if there is a tax rule defined for the vertical and player country
	- accordingly to tax rule defined (win, netwin) calculates the tax amount
	- at same time returns usefull information: 
			- if tax is in 'deferred' or 'onreturn' mode.
			- tax_cycle_id if is the case of deferred tax.

	Note: we need the clientID to get the player country on clients_locations.
		  we could discover the clientID using clientStatID but we need to avoid extra queries/joins. 
		  from where TaxCalculateTax is called we already have this info.

*/
	DECLARE taxEnabled, taxEnabledForVertical, taxOnGrossWin, taxRuleType TINYINT(1) DEFAULT 0;
    DECLARE countryTaxID, countryID BIGINT DEFAULT 0;
    DECLARE result VARCHAR(500) DEFAULT '';
	DECLARE taxPercentage, preTaxNetWin  DECIMAL(18,5) DEFAULT 0;

	-- CHECK IF TAX IS ACTIVE
	SELECT value_bool INTO taxEnabled FROM gaming_settings WHERE name='TAX_ON_GAMEPLAY_ENABLED';
	SET taxAmount = 0;

    IF (taxEnabled) THEN

		-- CHECK IF TAX IS ENABLED FOR THE VERTICAL
		SELECT cl.country_id, (gc.casino_tax AND (licenseTypeID = 1)) OR (gc.sports_tax AND (licenseTypeID = 3)) OR (gc.poker_tax AND (licenseTypeID = 2))
		INTO countryID, taxEnabledForVertical
		FROM clients_locations as cl
		JOIN gaming_countries as gc ON gc.country_id = cl.country_id
		WHERE cl.client_id = clientID 
		AND gc.is_active = 1
		AND cl.is_active = 1;

		IF (taxEnabledForVertical) THEN -- TAX IS ENABLED FOR THE VERTICAL

			-- CHECK TAX RULE DEFINED FOR THE VERTICAL & COUNTRY
			SELECT 	gct.country_tax_id, gct.tax_rule_type_id, gct.tax_percentage, gct.applied_on, gtc.tax_cycle_id
			INTO countryTaxID, taxRuleType, taxPercentage, appliedOn, taxCycleID
			FROM gaming_country_tax AS gct
			LEFT JOIN gaming_tax_cycles AS gtc ON gtc.country_tax_id = gct.country_tax_id -- left join cause the query is also for non deferred
						AND gtc.client_stat_id = clientStatID 
						AND gtc.is_active = 1 
						AND NOW() BETWEEN gtc.cycle_start_date AND gtc.cycle_end_date
			WHERE 
				gct.country_id 		= countryID 
			AND gct.licence_type_id = licenseTypeID 
			AND gct.is_current 		= 1 
			AND gct.is_active 		= 1
			AND NOW() BETWEEN date_start AND date_end
			LIMIT 1;

			IF (countryTaxID > 0) THEN 	-- THERE IS A TAX RULE DEFINED FOR THAT VERTICAL & PLAYER COUNTRY
						
				-- taxRuleType = 1, TAX ON BET NOT IMPLEMENTED

				IF (taxRuleType = 2) THEN -- TAX ON WIN

					SET taxAmount = winAmount * taxPercentage;

				ELSEIF (taxRuleType = 3) THEN -- TAX ON NETWIN

					SET preTaxNetWin = winAmount - betAmount;

					IF (appliedOn = 'OnReturn') THEN
						-- just tax if is >0
						IF (preTaxNetWin > 0) THEN
							SET taxAmount = preTaxNetWin  * taxPercentage;
						END IF;
					ELSEIF (appliedOn = 'Deferred') THEN
						-- tax a loss also
						-- taxAmount could be negative if is deferred. 
						-- we will keep the negative value in gaming_game_plays.amount_tax_player
						-- but we only add to gaming_client_stats.deferred_tax (current cumulative deferred tax) if is >0
						SET taxAmount = preTaxNetWin  * taxPercentage;
					END IF;

				END IF;
			END IF; -- tax rule defined for the vertical & player country

		END IF; -- taxEnabledForVertical

	END IF; -- taxEnabled
END$$

DELIMITER ;

