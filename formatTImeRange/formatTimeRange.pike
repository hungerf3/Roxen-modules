constant cvs_version = "$Id: $";
constant thread_safe=1;

#include <module.h>
inherit "module";

#define LOCALE(X,Y)     _DEF_LOCALE("mod_formatrange",X,Y)


#define MINUTE  60
#define HOUR  60*MINUTE
#define DAY  24*HOUR
#define WEEK  7*DAY
#define YEAR  365*DAY
#define DECADE  10*YEAR
#define CENTURY  100*YEAR

constant module_type = MODULE_TAG;
LocaleString module_name = LOCALE(1,"FormatRange");
LocaleString module_doc  =
  LOCALE(2,"Adds an extra container tag, &lt;formatrange&gt; that "
	   "Parses a SQL time range, and displays it as text." );



int ParseTimeRange(string aTime)
{
  array(int) parts = (array(int)) (aTime/":");
  return 60*60*parts[0]+
    60*parts[1]+
    parts[2];
}

string FormatTimeRange(int aTimeRange)
{
  string result = "";

  array TimeParts = ({
    ({"Centuries", CENTURY}),
    ({"Decades", DECADE}),
    ({"Years", YEAR}),
    ({"Weeks", WEEK}),
    ({"Days", DAY}),
    ({"Hours", HOUR}),
    ({"Minutes", MINUTE}),
    ({"Seconds", 1})
  });

  foreach (TimeParts, array TimePart)
    {
      if (aTimeRange > TimePart[1])
	{
	  result += sprintf(" %d %s",
			    aTimeRange/TimePart[1],
			    TimePart[0]);
	  aTimeRange%=TimePart[1];
	}
    }
  return result;
}

string simpletag_formatrange(string tag_name, mapping arguments, string contents, RequestID id)
{
  return FormatTimeRange(ParseTimeRange(contents));
}