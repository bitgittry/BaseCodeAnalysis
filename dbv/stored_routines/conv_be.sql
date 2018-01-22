
DROP function IF EXISTS `CONV_BE`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION CONV_BE(rawValue DECIMAL(18,5), nullAsZero TINYINT(1))
  RETURNS DECIMAL(18,5)
BEGIN
  -- ---------------------------------------------------------------------------------------------
  -- Simple utility function for common handling of Backend format conversion for currency amounts
  -- use on column select as:
  -- SELECT conv_be(current_real_balance, 1) FROM ...
  --  Params: 
  --  	rawValue: value to conditionally convert
  --	nullAsZero: boolean flag - if input value is null, function will return 0
  -- ----------------------------------------------------------------------------------------------
  
  IF (rawValue IS NULL AND nullAsZero) THEN
	-- Null => return 0
    RETURN 0; 
  ELSEIF (rawValue IS NULL) THEN
    -- Return Null
    RETURN rawValue;
  END IF;
  
  -- This will apply per-session
  IF (@conv_be_enabled_flag IS NULL) THEN
	-- and retrieve only once until session is over
    SELECT gs.value_bool INTO @conv_be_enabled_flag FROM gaming_settings gs WHERE gs.name = 'BACKEND_CONVERTION_USE_EXTERNAL_FORMAT';
  END IF;
  
  IF (@conv_be_enabled_flag) THEN
    RETURN rawValue / 100;
  ELSE
    RETURN rawValue;
  END IF;
END$$

DELIMITER ;