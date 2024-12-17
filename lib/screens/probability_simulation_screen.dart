import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simulation_app/services/excel_prob_service.dart';
import 'dart:io';
import 'dart:math';

class ProbabilitySimulationScreen extends StatefulWidget {
  const ProbabilitySimulationScreen({super.key});

  @override
  _ExcelSimulationScreenState createState() => _ExcelSimulationScreenState();
}

class _ExcelSimulationScreenState extends State<ProbabilitySimulationScreen> {
  List<List<String>> excelData = [];
  List<List<String>> analysisData = [];
  List<List<String>> newSimulationData = [];
  bool isExcelLoaded = false;
  bool isExcelGenerated = false;
  bool isExporting = false;
  String? _filePath = '';
  int customerNum = 1;
  static bool isDarkMode = false; // Track the current theme mode
  late ExcelProbService service;
  final TextEditingController _custNumController = TextEditingController();

  @override
  void initState() {
    super.initState();
    service = ExcelProbService(excelData, analysisData, newSimulationData);
    _loadDarkModePreference();
  }

  Future<void> _loadDarkModePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _saveDarkModePreference(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  Future<void> pickAndReadExcelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null) {
        _filePath = result.files.single.path;
        var bytes = File(_filePath!).readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);

        if (excel.tables.isNotEmpty) {
          String firstTableName = excel.tables.keys.first;
          var rows = excel.tables[firstTableName]?.rows;

          if (rows != null && rows.isNotEmpty) {
            excelData = rows
                .skip(1)
                .map((row) =>
                    row.map((cell) => cell?.value?.toString() ?? '').toList())
                .toList();
            isExcelLoaded = true;
          } else {
            excelData = [
              ['Error:', 'The Excel sheet is empty or invalid.']
            ];
            isExcelLoaded = false;
          }
        }
      }
    } catch (e) {
      excelData = [
        ['Error:', e.toString()]
      ];
      isExcelLoaded = false;
    }
    setState(() {});
  }

  // الدالة التي تقوم بإنشاء جدول التحليل
  void generateServiceAnalysis() {
    analysisData = [];
    Map<String, List<int>> serviceDurations = {};
    Map<String, int> serviceFrequency = {};
    double cumulativeProbability = 0;

    for (var row in excelData) {
      String service = row[2];
      int duration = int.tryParse(row[3]) ?? 0;

      serviceDurations.putIfAbsent(service, () => []).add(duration);
      serviceFrequency[service] = (serviceFrequency[service] ?? 0) + 1;
    }

    int totalServices = serviceFrequency.values.fold(0, (a, b) => a + b);
    int previousTo = 0;
    int custIdCounter = 1;

    serviceDurations.forEach((service, durations) {
      double averageDuration =
          durations.reduce((a, b) => a + b) / durations.length;
      double probability = serviceFrequency[service]! / totalServices;
      cumulativeProbability += probability;

      int to = (cumulativeProbability * 100).round();
      int from = analysisData.isEmpty ? 1 : previousTo + 1;

      analysisData.add([
        custIdCounter.toString(),
        service,
        averageDuration.toStringAsFixed(2),
        probability.toStringAsFixed(2),
        cumulativeProbability.toStringAsFixed(2),
        from.toString(),
        to.toString(),
      ]);

      previousTo = to;
      custIdCounter++;
    });

    setState(() {});
  }

  void generateNewSimulationTable() {
    newSimulationData = [];
    customerNum = int.tryParse(_custNumController.text) ?? 1;

    // الحصول على أقل وأكبر قيمة من عمود interval في الجدول المعطى
    List<int> intervals =
        excelData.map((row) => int.tryParse(row[1]) ?? 0).toList();
    int minInterval = intervals.reduce(min);
    int maxInterval = intervals.reduce(max);

    int previousArrivalClock = 0;
    double previousEnd = 0.0;

    for (int i = 0; i < customerNum; i++) {
      int custId = i + 1;

      // حساب interArrival كرقم عشوائي بين minInterval و maxInterval
      int interArrival =
          minInterval + Random().nextInt(maxInterval - minInterval + 1);

      // حساب arrivalClock كقيمة int
      int arrivalClock =
          i == 0 ? interArrival : interArrival + previousArrivalClock;

      // توليد الكود بشكل عشوائي ضمن حدود 'From' و 'To' في analysisData
      int minCode = int.parse(analysisData.first[5]);
      int maxCode = int.parse(analysisData.last[6]);
      int code = minCode + Random().nextInt(maxCode - minCode + 1);

      // البحث عن الخدمة المناسبة في analysisData بناءً على الكود
      String service = '';
      double avgDuration = 0;
      for (var row in analysisData) {
        int from = int.parse(row[5]);
        int to = int.parse(row[6]);
        if (code >= from && code <= to) {
          service = row[1];
          avgDuration = double.parse(row[2]);
          break;
        }
      }

      // حساب start و end كقيم double
      double start = i == 0 ? arrivalClock.toDouble() : previousEnd;
      double end = start + avgDuration;

      // حساب حالة العميل (state)
      String state;
      if (i == 0) {
        // للصف الأول، يتم تحديد الحالة بناءً على interArrival
        state = interArrival > 0 ? "wait" : "busy";
      } else {
        // لبقية الصفوف، يتم تطبيق الشرط المعطى
        state = (start - previousEnd) > 0 ? "wait" : "busy";
      }

      // حساب وقت الانتظار customerWait وضبطه ليكون صفرًا في حالة كان أقل من الصفر
      double customerWait = start - arrivalClock;
      if (customerWait < 0) customerWait = 0;

      // إضافة الصف إلى newSimulationData مع التحويل إلى نص لتنسيق العرض
      newSimulationData.add([
        custId.toString(),
        interArrival.toString(),
        arrivalClock.toString(),
        code.toString(),
        service,
        start.toStringAsFixed(1),
        avgDuration.toStringAsFixed(1),
        end.toStringAsFixed(1),
        state,
        customerWait.toStringAsFixed(1)
      ]);

      // تحديث القيم السابقة للصف التالي
      previousArrivalClock = arrivalClock;
      previousEnd = end;
    }

    setState(() {});
  }

  Future<void> saveExcelProbTables() async {
    // Initialize the service with the latest data right before saving
    final service = ExcelProbService(
        excelData, // Use updated excelData
        analysisData, // Use updated analysisData
        newSimulationData // Use updated newSimulationData
        );
    await service.saveExcelProbTables();
  }

  Widget buildTable(List<List<String>> data, List<String> headers) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Table(
          border: TableBorder.all(color: Colors.black),
          defaultColumnWidth: const FixedColumnWidth(100.0),
          children: [
            TableRow(
              children: headers
                  .map((header) => _buildCell(header, isHeader: true))
                  .toList(),
            ),
            ...data.map((row) {
              return TableRow(
                children: row.map((cell) => _buildCell(cell)).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(String content, {bool isHeader = false}) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: isHeader
          ? Colors.yellow
          : (isDarkMode ? Colors.grey[850] : Theme.of(context).cardColor),
      child: Text(
        content,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader
              ? Colors.black
              : (isDarkMode ? Colors.white : null), // Adjust text color
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDarkMode
          ? ThemeData.dark()
          : ThemeData.light(), // Set the theme based on the toggle
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Probability Simulation',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true, // Center the title for a clean design
          elevation: 4, // Add shadow for depth
          actions: [
            Tooltip(
              // Add a tooltip for better UX
              message:
                  isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              child: IconButton(
                icon: AnimatedSwitcher(
                  // Add a smooth transition when icon changes
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return RotationTransition(
                      turns: animation,
                      child: child,
                    );
                  },
                  child: Icon(
                    isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    key: ValueKey<bool>(isDarkMode), // Ensure smooth animations
                    color: isDarkMode ? Colors.yellowAccent : Colors.black54,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    isDarkMode = !isDarkMode; // Toggle the theme mode
                    _saveDarkModePreference(isDarkMode);
                  });
                },
              ),
            ),
          ],
          backgroundColor: isDarkMode
              ? Colors.black
              : Colors.white, // Adjust background color
          iconTheme: IconThemeData(
            color: isDarkMode
                ? Colors.white
                : Colors.black, // Icon color based on mode
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),
                TextField(
                  controller: _custNumController,
                  style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black87),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Enter Customer Number',
                    labelStyle: TextStyle(
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                    filled: true,
                    fillColor: isDarkMode
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey.shade200,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color:
                            isDarkMode ? Colors.white70 : Colors.grey.shade400,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color:
                            isDarkMode ? Colors.white70 : Colors.grey.shade400,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color:
                            isDarkMode ? Colors.cyanAccent : Colors.blueAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: pickAndReadExcelFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Choose Excel File',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 15),
                    ElevatedButton(
                      onPressed: () {
                        generateServiceAnalysis();
                        generateNewSimulationTable();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Run Simulation',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                if (isExcelLoaded)
                  buildTable(excelData,
                      ['Cust_id', 'Interval', 'Service', 'Duration']),
                const SizedBox(height: 20),
                if (analysisData.isNotEmpty)
                  Column(
                    children: [
                      const Text(
                        'Analysis Data Table',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      buildTable(
                        analysisData,
                        [
                          'Cust_id',
                          'ServType',
                          'Avg.Dur',
                          'Prob',
                          'Cum.Prob',
                          'From',
                          'To'
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                if (newSimulationData.isNotEmpty)
                  Column(
                    children: [
                      const Text(
                        'Simulation Data Table',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      buildTable(
                        newSimulationData,
                        [
                          'Cust_id',
                          'Interval',
                          'Arr.Clock',
                          'Code',
                          'Service',
                          'Start',
                          'Duration',
                          'End.Clock',
                          'State',
                          'Cust.Wait'
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                if (newSimulationData.isNotEmpty)
                  Stack(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: isExporting
                                ? null // Disable button while exporting
                                : () async {
                                    setState(() {
                                      isExporting = true;
                                    });

                                    await saveExcelProbTables();

                                    setState(() {
                                      isExporting = false;
                                      isExcelGenerated = true;
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isExporting
                                ? const SizedBox(
                                    height:
                                        24, // Set the height of the circular indicator
                                    width:
                                        24, // Set the width of the circular indicator
                                    child: CircularProgressIndicator(
                                      color: Colors
                                          .white, // Adjust the indicator color to fit the theme
                                      strokeWidth:
                                          3, // Set the stroke width for a more refined look
                                    ),
                                  )
                                : const Text(
                                    'Export to Excel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize:
                                          16, // Ensure the font size is appropriate for readability
                                      color: Colors
                                          .white, // Text color for light contrast
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: isExcelGenerated
                                ? () async {
                                    await service.openSavedFile();
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text(
                              'Open Excel File',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
