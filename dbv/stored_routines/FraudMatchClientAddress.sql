DROP procedure IF EXISTS `FraudMatchClientAddress`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudMatchClientAddress`(clientID BIGINT, OUT similarCount BIGINT)
BEGIN
  
  -- capitalized input parameters types
  -- Super Optimized
  -- Frank fix: SUP-6049 with NULLIF 
  -- Enhancement: INBUGLW-729 Run rule with compiled address when enabled
  
  DECLARE prefixLength INT DEFAULT 2;
  DECLARE levenstainMaxLength INT DEFAULT 64;
  
  DECLARE fullTextFilter VARCHAR(64) DEFAULT NULL;
  DECLARE levenstainText VARCHAR(127) DEFAULT NULL;
  DECLARE compiledAddress, tempCompiledAddress VARCHAR(1024) DEFAULT NULL;
  
  DECLARE currentFraudRuleId BIGINT;
  DECLARE currentSimilarityThreshold DECIMAL(18, 5);

  DECLARE isCompiledAddressEnabled TINYINT(1) DEFAULT 0;

  DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE gccaClientID BIGINT;
  DECLARE gccaCompiledAddress NVARCHAR(1024);

  DECLARE gccaCursor CURSOR FOR SELECT * FROM gcca;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;

  SELECT value_bool INTO isCompiledAddressEnabled FROM gaming_settings WHERE name='COUNTRY_COMPILED_ADDRESS_ENABLED';
  
  IF(isCompiledAddressEnabled = 1) THEN
    SET compiledAddress = ClientGetCompiledAddress(clientID, '|');
    SET fullTextFilter = TRIM(CONCAT_WS('* ', 
	   NULLIF(SUBSTR(ExtractAlphanumeric(IF(TRIM(compiledAddress) = '', NULL, TRIM(compiledAddress)), 1), 1, prefixLength + 1), ''),
	''));

    SET levenstainText = UPPER(RIGHT(CONCAT_WS(' ', IF(TRIM(compiledAddress) = '', NULL, TRIM(compiledAddress))), levenstainMaxLength));

  ELSE
    SELECT TRIM(CONCAT_WS('* ', 
	   NULLIF(SUBSTR(ExtractAlphanumeric(IF(TRIM(`address_1`) = '', NULL, TRIM(`address_1`)), 1), 1, prefixLength + 1), ''),
       NULLIF(SUBSTR(ExtractAlphanumeric(IF(TRIM(`address_2`) = '', NULL, TRIM(`address_2`)), 1), 1, prefixLength + 1), ''), 
	   NULLIF(SUBSTR(IF(TRIM(`city`) = '', NULL, TRIM(`city`)), 1, prefixLength), ''), 
	   NULLIF(SUBSTR(IF(TRIM(`postcode`) = '', NULL, TRIM(`postcode`)), 1, prefixLength), ''), 
       NULLIF(SUBSTR(IF(TRIM(`suburb`) = '', NULL, TRIM(`suburb`)), 1, prefixLength), ''), 
	   NULLIF(SUBSTR(IF(TRIM(`town_name`) = '', NULL, TRIM(`town_name`)), 1, prefixLength), ''), 
	   NULLIF(SUBSTR(IF(TRIM(`street_number`) = '', NULL, TRIM(`street_number`)), 1, prefixLength), ''),
	'')),
         UPPER(RIGHT(CONCAT_WS(' ',
			IF(TRIM(`address_1`) = '', NULL, TRIM(`address_1`)),
			IF(TRIM(`address_2`) = '', NULL, TRIM(`address_2`)),
			IF(TRIM(`city`) = '', NULL, TRIM(`city`)),
			IF(TRIM(`postcode`) = '', NULL, TRIM(`postcode`)),
			IF(TRIM(`suburb`) = '', NULL, TRIM(`suburb`)),
			IF(TRIM(`town_name`) = '', NULL, TRIM(`town_name`)),
			IF(TRIM(`street_number`) = '', NULL, TRIM(`street_number`))
		 ), levenstainMaxLength)) 
         INTO fullTextFilter, levenstainText
    FROM gaming_clients AS gc
    STRAIGHT_JOIN clients_locations ON clients_locations.client_id=gc.client_id AND clients_locations.is_primary
    WHERE gc.client_id=clientID;
  END IF;
  
  SELECT fraud_rule_id, similarity_threshold INTO currentFraudRuleId, currentSimilarityThreshold 
  FROM gaming_fraud_rules gfr 
  WHERE (gfr.`name` = 'similar_address' AND gfr.is_active = 1);
  
  SET similarCount = 0;
  
  IF currentFraudRuleId IS NOT NULL THEN
    
    DELETE FROM gaming_fraud_similarity_thresholds WHERE fraud_rule_id=currentFraudRuleId AND client_id_1=clientID;

    IF(isCompiledAddressEnabled = 1) THEN

      DROP TEMPORARY TABLE IF EXISTS gcca;
      CREATE TEMPORARY TABLE IF NOT EXISTS gcca (
        `client_id` bigint(20) NOT NULL,
        `compiled_address` varchar(1024) DEFAULT NULL,
        PRIMARY KEY (`client_id`),
        FULLTEXT KEY `compiled_address_ft_idx` (`compiled_address`)
      ) ENGINE=MyISAM;

      INSERT INTO gcca (`client_id`, `compiled_address`) 
      SELECT gaming_clients.client_id AS client_id, '' AS compiled_address
      FROM gaming_clients
      LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
      WHERE
        (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL) AND 
        gaming_clients.client_id!=clientID AND
        NOT EXISTS 
        (
          SELECT gfst.client_id_1 FROM gaming_fraud_similarity_thresholds gfst 
          WHERE gfst.fraud_rule_id = currentFraudRuleId AND gfst.client_id_1 = clientID AND gfst.client_id_2 = gaming_clients.client_id
        );

      -- MUST LOOT HERE TO CALCULATE compiled_address
      OPEN gccaCursor;
        gcca: LOOP
      
        SET noMoreRecords=0;
        FETCH gccaCursor INTO gccaClientID, gccaCompiledAddress;
        IF (noMoreRecords) THEN
            LEAVE gcca;
        END IF;
    
        SET tempCompiledAddress = ClientGetCompiledAddress(gccaClientID, '|');
		IF(tempCompiledAddress IS NOT NULL AND tempCompiledAddress <> '') THEN
          UPDATE gcca SET compiled_address=tempCompiledAddress WHERE client_id=gccaClientID;
        END IF;

      END LOOP gcca; 
      CLOSE gccaCursor;

      INSERT INTO gaming_fraud_similarity_thresholds (fraud_rule_id, client_id_1, client_id_2, similarity_threshold)
      SELECT currentFraudRuleId, clientID, x.client_id, ROUND(x.ratio, 4) 
      FROM (
		  SELECT client_id, LevenshteinRatio(
				levenstainText, 
				UPPER(RIGHT(CONCAT_WS(' ',
					IF(TRIM(`compiled_address`) = '', NULL, TRIM(`compiled_address`))
			 ), levenstainMaxLength)) 
          ) AS ratio 
		  FROM gcca
		  WHERE 
			(MATCH (`compiled_address`) AGAINST (fullTextFilter IN BOOLEAN MODE))
		  LIMIT 25
      ) AS x 
      WHERE x.ratio > currentSimilarityThreshold;

      DROP TEMPORARY TABLE IF EXISTS gcca;

    ELSE
      
      INSERT INTO gaming_fraud_similarity_thresholds (fraud_rule_id, client_id_1, client_id_2, similarity_threshold)
	  SELECT currentFraudRuleId, clientID, x.client_id, ROUND(x.ratio, 4) 
      FROM (
		  SELECT gc.client_id, LevenshteinRatio(
				levenstainText, 
				UPPER(RIGHT(CONCAT_WS(' ',
					IF(TRIM(`address_1`) = '', NULL, TRIM(`address_1`)),
					IF(TRIM(`address_2`) = '', NULL, TRIM(`address_2`)),
					IF(TRIM(`city`) = '', NULL, TRIM(`city`)),
					IF(TRIM(`postcode`) = '', NULL, TRIM(`postcode`)),
					IF(TRIM(`suburb`) = '', NULL, TRIM(`suburb`)),
					IF(TRIM(`town_name`) = '', NULL, TRIM(`town_name`)),
					IF(TRIM(`street_number`) = '', NULL, TRIM(`street_number`))
			 ), levenstainMaxLength)) 
          ) AS ratio 
		  FROM clients_locations cl FORCE INDEX (fraud_similar_address)
		  STRAIGHT_JOIN gaming_clients gc ON (gc.client_id = cl.client_id)
		  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gc.client_id
		  WHERE 
			(MATCH (`address_1`, `address_2`, `city`, `postcode`, `suburb`, `town_name`, `street_number`) AGAINST (fullTextFilter IN BOOLEAN MODE)) AND 
			 (
              (gaming_fraud_rule_client_settings.block_account = 0 
				OR gaming_fraud_rule_client_settings.block_account = NULL) AND gc.is_account_closed=0
			  ) AND 
              gc.client_id!=clientID AND 
              NOT EXISTS 
              (
				SELECT gfst.client_id_1 FROM gaming_fraud_similarity_thresholds gfst 
                WHERE gfst.fraud_rule_id = currentFraudRuleId AND gfst.client_id_1 = clientID AND gfst.client_id_2 = gc.client_id
			  ) 
		  LIMIT 25
	  ) AS x 
	  WHERE x.ratio > currentSimilarityThreshold
	  ON DUPLICATE KEY UPDATE similarity_threshold=VALUES(similarity_threshold);

    END IF;

    SELECT COUNT(*) INTO similarCount FROM gaming_fraud_similarity_thresholds WHERE fraud_rule_id = currentFraudRuleId AND client_id_1 = clientID;
    
  END IF;
  
END$$

DELIMITER ;

