import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_officechart/officechart.dart';

class ExcelService {
  final List<List<dynamic>>? _inputTable;
  final List<List<dynamic>>? _simulationTable;
  final String? _filePath;
  final List<Map<String, dynamic>> _events = [];
  String? _savedFilePath;

  ExcelService(this._filePath, this._inputTable, this._simulationTable);

  Future<void> createExcelTables() async {
    if (_simulationTable == null || _simulationTable.isEmpty) {
      if (kDebugMode) {
        print('No data available to create events.');
      }
      return;
    }

    _events.clear();

    for (int i = 0; i < _simulationTable.length; i++) {
      final entry = _simulationTable[i]; // Use safe access to avoid null
      var custId = entry.isNotEmpty ? entry[0] : null;
      var arrivalTime = entry.length > 2 ? entry[2] : null;
      var departureTime = entry.length > 7 ? entry[7] : null;

      if (custId != null && arrivalTime != null && departureTime != null) {
        try {
          if (_isNumeric(custId.toString()) &&
              _isNumeric(arrivalTime.toString()) &&
              _isNumeric(departureTime.toString())) {
            int custNum = int.parse(custId.toString());
            int arrival = int.parse(arrivalTime.toString());
            int departure = int.parse(departureTime.toString());

            _events.add({
              'Event_Type': 'Arrival',
              'Cust_Num': custNum,
              'Clock_Time': arrival,
            });
            _events.add({
              'Event_Type': 'Departure',
              'Cust_Num': custNum,
              'Clock_Time': departure,
            });
          } else {
            if (kDebugMode) {
              print('Non-numeric data found in entry: $entry');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing values: $e');
          }
        }
      } else {
        if (kDebugMode) {
          print('Missing data in entry: $entry');
        }
      }
    }
    await saveEventsToExcel();
  }

  bool _isNumeric(String str) {
    return int.tryParse(str) != null;
  }

  Future<void> saveEventsToExcel() async {
    // Request storage permission
    await _requestStoragePermission();

    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];

    // Style for header cells: yellow background, center alignment, and border
    final headerStyle = workbook.styles.add('HeaderStyle');
    headerStyle.backColor = '#FFFF00'; // Yellow color
    headerStyle.hAlign = xlsio.HAlignType.center;
    headerStyle.bold = true;
    headerStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    // Style for content cells: center alignment and border
    final contentStyle = workbook.styles.add('ContentStyle');
    contentStyle.hAlign = xlsio.HAlignType.center;
    contentStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    // Define headers for the inputTable.
    final inputHeaders = [
      'Code',
      'Service',
      'Duration',
    ]; // Define your specific headers here

    // Insert inputTable headers in the first row with header style
    for (int i = 0; i < inputHeaders.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(inputHeaders[i]);
      cell.cellStyle = headerStyle;
    }

    // Insert _inputTable data starting from row 2
    if (_inputTable != null) {
      for (int i = 0; i < _inputTable.length; i++) {
        final row = _inputTable[i];
        for (int j = 0; j < row.length; j++) {
          final cell = sheet.getRangeByIndex(i + 2, j + 1);

          // Check if the column is the first or third column (index 0 and 2)
          if (j == 0 || j == 2) {
            // Check if the value is numeric and set it as a number
            if (row[j] is num) {
              cell.setNumber(row[j]); // Insert as number if it's numeric
            } else {
              // Convert string to number if the value is a valid number as string
              var parsedValue = double.tryParse(row[j].toString());
              if (parsedValue != null) {
                cell.setNumber(parsedValue); // Set the parsed value as a number
              } else {
                cell.setText(row[j].toString()); // Otherwise set as text
              }
            }
          } else {
            // For columns other than the first and third, set as text
            cell.setText(row[j].toString());
          }

          cell.cellStyle = contentStyle; // Apply content style
        }
      }
    }

    // Define headers for the simulationData table.
    final headers = [
      'Cust_id',
      'Interval',
      'Arr.Clock',
      'code',
      'Service',
      'Start',
      'Duration',
      'End_Clock',
      'State Ser',
      'Cust Wait'
    ];

// Insert headers starting from row 8.
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(8, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle = headerStyle;
    }

// Insert simulationData and formulas starting from row 9.
    for (int i = 0; i < _simulationTable!.length; i++) {
      final row = _simulationTable[i];
      for (int j = 0; j < row.length; j++) {
        final cell = sheet.getRangeByIndex(i + 9, j + 1);

        // For columns that require formulas
        if (j == 1 && i > 0) {
          // Interval = Random between 1 and 3
          cell.setFormula('=RANDBETWEEN(1, 3)');
        } else if (j == 2 && i > 0) {
          // Arr.Clock = current Interval + previous row's Arr.Clock
          cell.setFormula('=B${i + 9} + C${i + 8}');
        } else if (j == 3) {
          // Code = Random between A2 : A5
          cell.setFormula('=RANDBETWEEN(\$A\$2,\$A\$5)');
        } else if (j == 4) {
          // Service = LOOKUP(D${i+9},$A$2:$A$5,$B$2:$B$5)
          cell.setFormula('=LOOKUP(D${i + 9},\$A\$2:\$A\$6,\$B\$2:\$B\$6)');
        } else if (j == 5 && i != 0) {
          // Start = Max of Arr.Clock and End_Clock
          cell.setFormula('=MAX(C${i + 9}, H${i + 8})');
        } else if (j == 6) {
          // Duration = LOOKUP(G${i+9},$A$2:$A$5,$C$2:$C$5)
          cell.setFormula('=LOOKUP(D${i + 9},\$A\$2:\$A\$6,\$C\$2:\$C\$6)');
        } else if (j == 7) {
          // End_Clock = Start + Duration
          cell.setFormula('=F${i + 9} + G${i + 9}');
        } else if (j == 8 && i == 0) {
          // Server State = =IF([@Column2]>0,"Wait","Busy")
          cell.setFormula('=IF(B${i + 9}>0, "Wait", "Busy")');
        } else if (j == 8) {
          // Server State = =IF([@Column2]>0,"Wait","Busy")
          cell.setFormula('=IF(F${i + 9}-H${i + 9}>0, "Wait", "Busy")');
        } else if (j == 9) {
          // Cust Wait = Start - Arr.Clock
          cell.setFormula('=F${i + 9} - C${i + 9}');
        } else {
          // For non-formula cells, insert the data from _simulationTable
          cell.setText(row[j].toString());
        }
        cell.cellStyle = contentStyle;
      }
    }

    // Define headers for the second table and start from row after the first table.
    final secondTableStartRow = _simulationTable.length + 10;
    sheet.getRangeByName('A$secondTableStartRow').setText('Event_Type');
    sheet.getRangeByName('B$secondTableStartRow').setText('Cust_Num');
    sheet.getRangeByName('C$secondTableStartRow').setText('Clock_Time');
    sheet
        .getRangeByName('A$secondTableStartRow:C$secondTableStartRow')
        .cellStyle = headerStyle;

    // Insert _events data starting from the row below second table headers.
    for (int i = 0; i < _events.length; i++) {
      final event = _events[i];
      final cellA = sheet.getRangeByName('A${i + secondTableStartRow + 1}');
      cellA.setText(event['Event_Type']);
      cellA.cellStyle = contentStyle;

      final cellB = sheet.getRangeByName('B${i + secondTableStartRow + 1}');
      cellB.setNumber(event['Cust_Num'].toDouble());
      cellB.cellStyle = contentStyle;

      final cellC = sheet.getRangeByName('C${i + secondTableStartRow + 1}');
      cellC.setNumber(event['Clock_Time'].toDouble());
      cellC.cellStyle = contentStyle;
    }

    // Set up chart to start at row 8.
    final ChartCollection charts = ChartCollection(sheet);
    final Chart chart = charts.add();
    chart.chartType = ExcelChartType.lineMarkers;
    chart.dataRange = sheet.getRangeByName(
        'A$secondTableStartRow:C${secondTableStartRow + _events.length}');
    chart.isSeriesInRows = false;
    chart.chartTitle = 'Customers In The System';
    chart.chartTitleArea.bold = true;
    chart.chartTitleArea.size = 10;
    chart.chartTitleArea.color = "#050505";

    // Additional chart formatting
    final ChartSerie serie1 = chart.series[0];
    serie1.dataLabels.isValue = true;
    serie1.dataLabels.textArea.bold = true;
    serie1.dataLabels.textArea.size = 10;
    serie1.dataLabels.textArea.color = '#000000';
    serie1.dataLabels.textArea.fontName = 'Arial';
    serie1.linePattern = ExcelChartLinePattern.longDash;
    serie1.linePatternColor = '#F40829';

    final ChartSerie serie2 = chart.series[1];
    serie2.dataLabels.isValue = true;
    serie2.dataLabels.textArea.bold = true;
    serie2.dataLabels.textArea.size = 10;
    serie2.dataLabels.textArea.color = '#920467';
    serie2.dataLabels.textArea.fontName = 'Arial';
    serie2.linePattern = ExcelChartLinePattern.longDash;
    serie2.linePatternColor = '#08A2F4';

    chart.legend!.position = ExcelLegendPosition.right;
    chart.linePattern = ExcelChartLinePattern.solid;
    chart.linePatternColor = "#2F4F4F";
    chart.plotArea.linePattern = ExcelChartLinePattern.solid;
    chart.plotArea.linePatternColor = '#2F4F4F';

    chart.topRow = secondTableStartRow;
    chart.bottomRow = secondTableStartRow + 13;
    chart.leftColumn = 5;
    chart.rightColumn = 16;
    sheet.charts = charts;

    final List<int> bytes = workbook.saveSync();
    workbook.dispose();

    final directory = await getApplicationDocumentsDirectory();
    final savedFile = File('${directory.path}/_events.xlsx');

    try {
      await savedFile.writeAsBytes(bytes);
      _savedFilePath = savedFile.path;
      if (kDebugMode) {
        print('Events saved to Excel at: $_savedFilePath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving Excel file: $e');
      }
    }
  }

  Future<void> _requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
  }

  Future<void> openSavedFile() async {
    if (_savedFilePath != null) {
      final result = await OpenFile.open(_savedFilePath);
      if (result.message != 'Done') {
        if (kDebugMode) {
          print('Failed to open file: ${result.message}');
        }
      }
    } else {
      if (kDebugMode) {
        print('No file path available to open.');
      }
    }
  }

  List<Map<String, dynamic>> get events => _events;
  String? get filePath => _filePath;
  String? get savedFilePath => _savedFilePath;
}
