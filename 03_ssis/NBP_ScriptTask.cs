// =====================================================================
// NFX – Nike Foreign Exchange | Kod C# do SSIS Script Task
// Pakiet: Load_NBP_FX.dtsx  ->  Control Flow  ->  Script Task
// Jezyk: Microsoft Visual C# (ScriptMain.Main).
// Zmienne SSIS (ReadOnlyVariables): User::dateStart, User::dateEnd (string yyyy-MM-dd),
//                                   User::connStr (OLE DB/ADO.NET do NFX_DW).
//
// Realizuje DOKLADNIE te sama logike co 02_etl/nbp_fetch.py:
//   * tabele A i B (mid), segmentacja zakresu na <= 90 dni (limit NBP 93),
//   * HttpClient (HTTPS!), parsowanie JSON (System.Text.Json),
//   * 404 (dzien wolny) -> pomijamy,
//   * zapis do staging.stg_fx_rates (SqlBulkCopy).
// Wynik tej tabeli laduja dalej Execute SQL Task -> dw.usp_LoadFactExchangeRates.
// =====================================================================
#region Namespaces
using System;
using System.Data;
using System.Net.Http;
using System.Text.Json;
using System.Collections.Generic;
using System.Data.SqlClient;
using Microsoft.SqlServer.Dts.Runtime;
#endregion

namespace ST_NFX_NBP
{
    public partial class ScriptMain : Microsoft.SqlServer.Dts.Tasks.ScriptTask.VSTARTScriptObjectModelBase
    {
        private static readonly HttpClient http = new HttpClient();
        const string BASE = "https://api.nbp.pl/api/exchangerates/tables";
        static readonly string[] TABLES = { "A", "B" };
        const int MAX_SPAN = 90;

        public void Main()
        {
            DateTime start = DateTime.Parse((string)Dts.Variables["User::dateStart"].Value);
            DateTime end   = DateTime.Parse((string)Dts.Variables["User::dateEnd"].Value);
            string connStr = (string)Dts.Variables["User::connStr"].Value;

            var rows = new List<FxRow>();
            try
            {
                foreach (var t in TABLES)
                    foreach (var (segStart, segEnd) in Segments(start, end, MAX_SPAN))
                        rows.AddRange(FetchSegment(t, segStart, segEnd));

                BulkInsert(connStr, rows);
                Dts.TaskResult = (int)ScriptResults.Success;
            }
            catch (Exception ex)
            {
                Dts.Events.FireError(0, "NBP_ScriptTask", ex.ToString(), "", 0);
                Dts.TaskResult = (int)ScriptResults.Failure;
            }
        }

        // podzial zakresu na segmenty <= span dni (limit API NBP = 93)
        private IEnumerable<(DateTime, DateTime)> Segments(DateTime s, DateTime e, int span)
        {
            var cur = s;
            while (cur <= e)
            {
                var segEnd = cur.AddDays(span - 1);
                if (segEnd > e) segEnd = e;
                yield return (cur, segEnd);
                cur = segEnd.AddDays(1);
            }
        }

        private List<FxRow> FetchSegment(string table, DateTime from, DateTime to)
        {
            var result = new List<FxRow>();
            string url = $"{BASE}/{table}/{from:yyyy-MM-dd}/{to:yyyy-MM-dd}/?format=json";
            var resp = http.GetAsync(url).GetAwaiter().GetResult();
            if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return result; // dzien wolny
            resp.EnsureSuccessStatusCode();
            string json = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();

            using var doc = JsonDocument.Parse(json);
            foreach (var tbl in doc.RootElement.EnumerateArray())
            {
                string no  = tbl.GetProperty("no").GetString();
                string eff = tbl.GetProperty("effectiveDate").GetString();
                foreach (var rt in tbl.GetProperty("rates").EnumerateArray())
                {
                    result.Add(new FxRow
                    {
                        TableType = table,
                        TableNo   = no,
                        EffectiveDate = eff,
                        Code = rt.GetProperty("code").GetString(),
                        NamePl = rt.GetProperty("currency").GetString(),
                        Mid = rt.TryGetProperty("mid", out var m) ? m.GetDecimal() : (decimal?)null
                    });
                }
            }
            return result;
        }

        private void BulkInsert(string connStr, List<FxRow> rows)
        {
            var dt = new DataTable();
            dt.Columns.Add("table_type", typeof(string));
            dt.Columns.Add("table_no", typeof(string));
            dt.Columns.Add("effective_date", typeof(string));
            dt.Columns.Add("trading_date", typeof(string));
            dt.Columns.Add("code", typeof(string));
            dt.Columns.Add("currency_name_pl", typeof(string));
            dt.Columns.Add("mid", typeof(string));
            dt.Columns.Add("bid", typeof(string));
            dt.Columns.Add("ask", typeof(string));
            foreach (var r in rows)
                dt.Rows.Add(r.TableType, r.TableNo, r.EffectiveDate, null, r.Code, r.NamePl,
                            r.Mid?.ToString(System.Globalization.CultureInfo.InvariantCulture), null, null);

            using var cn = new SqlConnection(connStr);
            cn.Open();
            using (var cmd = new SqlCommand("TRUNCATE TABLE staging.stg_fx_rates", cn)) cmd.ExecuteNonQuery();
            using var bulk = new SqlBulkCopy(cn) { DestinationTableName = "staging.stg_fx_rates" };
            foreach (DataColumn c in dt.Columns) bulk.ColumnMappings.Add(c.ColumnName, c.ColumnName);
            bulk.WriteToServer(dt);
        }

        private class FxRow
        {
            public string TableType, TableNo, EffectiveDate, Code, NamePl;
            public decimal? Mid;
        }
        enum ScriptResults { Success = 0, Failure = 1 }
    }
}
