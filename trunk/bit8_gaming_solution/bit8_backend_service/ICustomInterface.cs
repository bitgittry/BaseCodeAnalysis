using bit8.customclasses;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8.interfaces
{
    public interface ICustomInterface
    {
        void MethodC1(ICustomInterface2 cclass1, String string1);

        void MethodC2(CustomClass2 cclass1, string string1);

        void MethodC3();
    }

    public interface ICustomInterface2
    {
        void DoStuff();
    }
}
