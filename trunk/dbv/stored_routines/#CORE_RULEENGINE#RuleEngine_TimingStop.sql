

DROP procedure IF EXISTS `RuleEngine_TimingStop`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngine_TimingStop`(process VARCHAR(120))
root: BEGIN
  
  DECLARE isLogActive TINYINT(1);
  declare lastTime TIMESTAMP(6);
  declare nowTime TIMESTAMP(6);
  declare df BIGINT(20);
  select value_bool INTO isLogActive from gaming_settings where name='RULE_ENGINE_LOG_ENABLED';

  if (isLogActive=1) THEN
  	if (EXISTS(select id from system_timing where ProcedureName=process)) THEN
  		set lastTime=(select datestamp from system_timing where ProcedureName=process);
  		update system_timing set counter=ifnull(counter,0)+1 where  ProcedureName=process;
      set nowTime=now(6);
      set df=TIMESTAMPDIFF(MICROSECOND,lastTime,now(6))/1000;
  		update system_timing set TotMSec=(ifnull(TotMSec,0)+case when df>0 then df else 0 end) where ProcedureName=process;
  		update system_timing set AvgMSec=TotMSec/counter where  ProcedureName=process;
  		update system_timing set LastMSec=case when df>0 then df else 0 end where ProcedureName=process;
  	end if;
  end if;
  

END root$$

DELIMITER ;
