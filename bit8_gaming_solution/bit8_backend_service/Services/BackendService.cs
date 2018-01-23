using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using bit8.interfaces;
using bit8.customclasses;
using bit8_utilities.ImpactTool;
using bit8_backend_service.b.b1;
using ClassLibrary1;
using System.Data;
//using bit8_backend_service.Services;

namespace bit8.customclasses
{
    public class BackendService : IBackendService
    {
        public void UserGetAllUserRestrictions(string param)
        {
            Method4(); // 1111sadfasdfsasdfasdfasadfasdfasdfsdfdf
            Method2Nuovo(); // asdfasd
            var b = new BClass(); // asdf
            b.HelloWorld();//sasdfadf
            NuovoMetodoA2();

            var otherClass = new ClassFromOtherProject(); // asdfasdf
            otherClass.DoSomeStuff();

            // select * from users_groups_client_close_levels

            CallSql("select * from gaming_tax_cycle_game_sessions");

            // calling a stored procedure
            var cmd = GetCommandWrapper(); // fasfsd
            cmd.CommandText = "CommonWalletLogRequest";
            cmd.CommandType = CommandType.StoredProcedure;
            cmd.ExecuteNonQuery();
        }

        private void CallSql(string v)
        {
            throw new NotImplementedException(); // asdf
        }

        private DbCommandWrapper GetCommandWrapper()
        {
            return null; // asdf
        }

        private class DbCommandWrapper
        {
            public string CommandText { get; internal set; }
            public object CommandType { get; internal set; }

            internal void ExecuteNonQuery()
            {
                throw new NotImplementedException();
            }
        }

        public void PlayerGetModuleData()
        {
            Method2Nuovo();///2agggaasdfasfdsdaasdfsdasdfasdffasdfsaasdfdfasdffasdf
            Method2("hello", "world");
            Method2(1, 2);//asdfaasdasasasdfdfaaasdfsdfsdfdffsadfsdasdfdfasdfasdf
            NuovoMetodo();
            NuovoMetodo1();//4a
            NewMethod();// 5a

            var baseItem = new Base<String>();
            baseItem.Hello("ciao ciao");

            new B1Class().Bau();

            Method2Nuovo();///2aasdfasdf
            Method2("hello", "world");
            Method2(1, 2);//3a
            NuovoMetodo();
            NuovoMetodo1();//4aasdf
            NewMethod();// 5aasdfasdfasdasdfasdf
            NuovoMetodo3();
        }

        private void NewMethod()
        {
        	// asdfasdf
        }

        private void NuovoMetodo1()
        {
            ////asdfsdfsasdfdfasdfasdfsdasdfasdf
        }

        private void NuovoMetodoA1()
        {
            // ddddddddaasdfsdaasdfsdf
        }

        private void NuovoMetodoA2()
        {
            // ddddddddaasdfsdasdfaasdfsdsadfasdasdfffasdfasdfasdf
        }

        private void NuovoMetodo3()
        {
            // ddddddddasdasdfaasdfsdfdddddasdf
        }

        private void NuovoMetodo()
        {

            // asdfsdfdsaasdfasdfsdfasdf
            // modifico NuovoMetodo()6
        }

        private void Method2Nuovo()
        {
            // blablablaaasdfasdfsfsdfasd asdfaaasdf
            // sfa sfsdaasdfasdf
            // asfsafdsdfsdasfsdfd
            
            // select * from users_groups_client_close_levels
        }

        private void Method2(string param1, string param2)
        {
            // asdfsdafsasdfdfasdfasdf
            // asfsd
        }

        private void Method2(int param1, int param2)
        {
            // asfsadfasdfasdfasdfaasdfasfdsasdf
        }

        private void Method4()
        {
            // asdfsadfsdfasdfasasdffdsadfsafsdfsadasdffasdfasdfasdsdsdfd
        }

        private void Method51()
        {
        }

        private void Method6()
        {
            //8a
        }
    }

    public class Base<T>
    {
        public void Hello(T param)
        {

        }
    }

    public class Base1
    {
        public void Hello(string param)
        {
            //9a
        }
    }
}
