using BaseForCodeAnalysis;
using bit8.interfaces;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8.customclasses
{
    public class CustomClass : ICustomInterface
    {
        public void MethodC1(ICustomInterface2 cclass1, string string1)
        {
            cclass1.DoStuff();

            var class2 = new CustomClass2();

            class2.DoStuff2(null, null, null, null, null, null, null);

        }

        public void MethodC2(CustomClass2 cclass1, string string1)
        {
            cclass1.DoStuff();

            var class2 = new CustomClass2();

            class2.DoStuff();
        }

        public void MethodC3()
        {
            throw new NotImplementedException();
        }
    }

    public class CustomClass2 : ICustomInterface2
    {
        public void DoStuff()
        {
            throw new NotImplementedException();
        }

        public void DoStuff2(
            ICustomInterface2[] list,
            List<ICustomInterface> list1,
            List<List<ICustomInterface>> list2,
            Dictionary<List<ICustomInterface>, List<ICustomInterface2>> list3,
            long[] myArray,
            String param1, 
            ICustomInterface param2)
        {
            throw new NotImplementedException();
        }
    }
}
