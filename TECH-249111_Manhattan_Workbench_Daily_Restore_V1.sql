/*
================================================================================
SCRIPT NAME:    TECH-249111_Manhattan_Workbench_Daily_Restore_V1.sql
TICKET ID:      TECH-249111
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-16
MODIFIED:       2026-11-16
VERSION:        v1.0

PURPOSE:
    RESTORE the standard daily 7a job after the one-time 09SEP2026 pull (same as original plus the history line).

SOURCE SYSTEM:  Manhattan shipment_level_analyzer (CLG-MAN2019 / Sybase)
TARGET SYSTEM:  DOMO Workbench job (dev-dice-app01) -> RAW_Manhattan_MonthlyData

NOTES:
    - Daily job normally requests LAST month (today 11/16 -> 10OCT2026).
    - The job UPDATE METHOD IS APPEND: leaving the one-time line in place would
      re-append September every day. Restore the Daily version right after the run.
================================================================================
*/

-------TECH-68118 Dale Shofner / Jim Cook 11/9/21   -----RAW_Manhattan_MonthlyData  schedule daily at 7am ; append update method
----Orin Wilcox owilcox@manh.com  -- technical contact at Manhattan Associates  678 597-6327
--tech-98104 - RELOAD BELOW 11/8/22 DALE SHOFNER
-- TECH-147849   Jim Cook  07/26/24  Need to purge January through April 2024 Data from the Profit Analyzer DOMO Database
-- TECH-232875   Dale Shofner 7/30/26   Can you purge the data for the 06JUN2026 (26006) Profit Analyzer scenario so that we can set the fixed data to be downloaded? - 
----                                    Mark A. Drewry Architect – Carrier Management Manhattan Associates P: 678.597.7527  M: 678.431.4239
 
declare @today datetime , @lastmonth date ,@parmvalue varchar(9), @mark_as_sent bit
select @today=getdate()
select @lastmonth= convert(varchar(10),dateadd(mm,-1,dateadd(dd,-(day(@today)-1),@today)),101)	----< first of last month
select @mark_as_sent = 1 --If you supply this input and set it to 0, then it will skip the step where it records that scenario as having been sent.  
                         --If you leave it off or set it to 1, then it will record the scenario as having been sent as expected.  
select @parmvalue = RIGHT('0' + cast(datepart(mm, @lastmonth) as varchar(2) ),2) + left( upper(DATENAME(mm, @lastmonth )) ,3)  + cast(datepart(yy, @lastmonth) as varchar(4) )


-------TEMPORARY below 11/9/21 dale  
--exec shipment_level_analyzer '01JAN2021', 0;  
--exec shipment_level_analyzer '02FEB2021', 0;
--exec shipment_level_analyzer '03MAR2021', 0;
--exec shipment_level_analyzer '04APR2021', 0;
--exec shipment_level_analyzer '05MAY2021', 0;
--exec shipment_level_analyzer '06JUN2021', 0;
--exec shipment_level_analyzer '07JUL2021', 0;
--exec shipment_level_analyzer '08AUG2021', 0;
--exec shipment_level_analyzer '09SEP2022', 1;   --- RELOADED 11/8/22 950AM DALE SHOFNER FOR TECH-98104
--exec shipment_level_analyzer '02FEB2023', 1;   --- RELOADED 3/22/2023 255p DALE SHOFNER FOR TECH-109930  --contact at Manhattan this time was Mark Drewry - mdrewry@manh.com 678-597-7527
--exec shipment_level_analyzer '03MAR2023', 1;   --- RELOADED 4/21/2023 900a DALE SHOFNER FOR TECH-112180  --contact at Manhattan this time was Mark Drewry - mdrewry@manh.com 678-597-7527
--exec shipment_level_analyzer '05MAY2024', 1;   --- RELOADED 7/11/2024 1045a DALE SHOFNER FOR TECH-144279
--exec shipment_level_analyzer '01JAN2024', 1;   --- RELOADED 07/26/2024 08:34 AM   Jim Cook for TECH-147849
--exec shipment_level_analyzer '02FEB2024', 1;   --- RELOADED 07/26/2024 08:44 AM   Jim Cook for TECH-147849
--exec shipment_level_analyzer '03MAR2024', 1;   --- RELOADED 07/26/2024 09:02 AM   Jim Cook for TECH-147849
--exec shipment_level_analyzer '04APR2024', 1;   --- RELOADED 07/26/2024 09:10 AM   Jim Cook for TECH-147849
--exec shipment_level_analyzer '01JAN2025', 1;   --- RELOADED 02/25/2025 10:30 AM   Jim Cook for TECH-167811 
-- exec shipment_level_analyzer '06JUN2026', 1;   --- RELOADED 07/30/2026 08:38 AM   Dale Shofner for TECH-232875  
-- exec shipment_level_analyzer '06JUN2026', 1;   --- RELOADED 07/31/2026 10:00 AM   Dale Shofner for TECH-232875  
--exec shipment_level_analyzer '07JUL2026', 1; == RELOADED 09/22/2026 09:30 AM   Dale Shofner for Mark Drewry
--exec shipment_level_analyzer '08AUG2026', 1; == RELOADED 10/20/2026 11:13 AM   Jim Cook for Mark Brian Williams
--exec shipment_level_analyzer '09SEP2026', 1; == RELOADED 11/16/2026 __:__ __   Jim Cook for TECH-249111  (Sept scenario not pulled; daily job requests last month)

 exec shipment_level_analyzer @parmvalue,@mark_as_sent


---this job is scheduled to run daily at 7a
