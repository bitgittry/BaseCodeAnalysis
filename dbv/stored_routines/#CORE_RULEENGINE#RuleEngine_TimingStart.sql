DROP procedure IF EXISTS `RuleEngine_TimingStart`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngine_TimingStart`(process VARCHAR(120))
root: BEGIN
  
  DECLARE isLogActive TINYINT(1);
  select value_bool INTO isLogActive from gaming_settings where name='RULE_ENGINE_LOG_ENABLED';

  if (isLogActive=1) THEN
  	if (NOT EXISTS(select id from system_timing where ProcedureName=process)) THEN
  		insert into system_timing (ProcedureName,datestamp,counter,totmsec,avgmsec) select process,now(6),0,0,0;
  	else
  		update system_timing set datestamp=now(6) where ProcedureName=process;
  	end if;
  end if;
  

END root$$

DELIMITER ;

