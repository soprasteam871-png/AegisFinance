import SwiftUI
import SwiftData
import Foundation
import LocalAuthentication

// MARK: - App Entry Point
@main
struct AegisFinanceApp: App {
    private let persistenceController = SecurityPersistenceController.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(persistenceController.container)
    }
}

// MARK: - Security Persistence Controller
public final class SecurityPersistenceController {
    public static let shared = SecurityPersistenceController()
    public let container: ModelContainer

    private init() {
        do {
            // Use a simple ModelContainer creation suitable for iOS (SwiftData default storage)
            self.container = try ModelContainer(for: [
                FixedIncomeEntity.self,
                UnexpectedIncomeEntity.self,
                ExpenseEntity.self,
                CategoryEntity.self
            ])
        } catch {
            fatalError("CRÍTICO: Falha ao inicializar banco de dados seguro: \(error.localizedDescription)")
        }
    }
}

// MARK: - Data Models (@Model)
@Model
public final class CategoryEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var iconName: String
    public var targetPercentageLimit: Decimal

    @Relationship(deleteRule: .cascade, inverse: \ExpenseEntity.category)
    public var expenses: [ExpenseEntity]

    public init(id: UUID = UUID(), name: String, iconName: String, targetPercentageLimit: Decimal) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.targetPercentageLimit = targetPercentageLimit
        self.expenses = []
    }
}

@Model
public final class FixedIncomeEntity {
    @Attribute(.unique) public var id: UUID
    public var sourceName: String
    public var grossAmount: Decimal
    public var dateAdded: Date
    public var isRecurringMonthly: Bool

    @Relationship(deleteRule: .nullify)
    public var linkedExpenses: [ExpenseEntity]

    public init(id: UUID = UUID(), sourceName: String, grossAmount: Decimal, dateAdded: Date = Date(), isRecurringMonthly: Bool = true) {
        self.id = id
        self.sourceName = sourceName
        self.grossAmount = grossAmount
        self.dateAdded = dateAdded
        self.isRecurringMonthly = isRecurringMonthly
        self.linkedExpenses = []
    }
}

@Model
public final class UnexpectedIncomeEntity {
    @Attribute(.unique) public var id: UUID
    public var sourceDescription: String
    public var amount: Decimal
    public var dateReceived: Date

    public init(id: UUID = UUID(), sourceDescription: String, amount: Decimal, dateReceived: Date = Date()) {
        self.id = id
        self.sourceDescription = sourceDescription
        self.amount = amount
        self.dateReceived = dateReceived
    }
}

@Model
public final class ExpenseEntity {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var amount: Decimal
    public var date: Date

    @Relationship
    public var category: CategoryEntity?

    @Relationship
    public var deductedFromIncome: FixedIncomeEntity?

    public init(id: UUID = UUID(), title: String, amount: Decimal, date: Date = Date(), category: CategoryEntity? = nil, deductedFromIncome: FixedIncomeEntity? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.category = category
        self.deductedFromIncome = deductedFromIncome
    }
}

// MARK: - Domain & Calculation Engine
public struct CategoryExpenseReport {
    public let categoryName: String
    public let totalSpent: Decimal
    public let percentageOfIncome: Decimal
    public let isExceedingBudget: Bool
}

public struct FinancialRecommendation {
    public let title: String
    public let description: String
    public let priority: Priority

    public enum Priority {
        case high, medium, low
    }
}

@ModelActor
public actor FinanceEngineActor {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func calculateNetFixedIncome() throws -> Decimal {
        let fixedIncomeDescriptor = FetchDescriptor<FixedIncomeEntity>()
        let fixedIncomes = try modelContext.fetch(fixedIncomeDescriptor)
        let totalFixedIncome = fixedIncomes.reduce(Decimal.zero) { $0 + $1.grossAmount }

        let expenseDescriptor = FetchDescriptor<ExpenseEntity>()
        let expenses = try modelContext.fetch(expenseDescriptor)
        let totalExpenses = expenses.reduce(Decimal.zero) { $0 + $1.amount }

        return totalFixedIncome - totalExpenses
    }

    public func analyzeCategories() throws -> [CategoryExpenseReport] {
        let fixedIncomeDescriptor = FetchDescriptor<FixedIncomeEntity>()
        let fixedIncomes = try modelContext.fetch(fixedIncomeDescriptor)
        let totalIncome = fixedIncomes.reduce(Decimal.zero) { $0 + $1.grossAmount }

        guard totalIncome > 0 else { return [] }

        let categoryDescriptor = FetchDescriptor<CategoryEntity>()
        let categories = try modelContext.fetch(categoryDescriptor)

        return categories.map { category in
            let totalSpent = category.expenses.reduce(Decimal.zero) { $0 + $1.amount }
            let percentage = totalSpent / totalIncome
            let isExceeding = percentage > category.targetPercentageLimit

            return CategoryExpenseReport(
                categoryName: category.name,
                totalSpent: totalSpent,
                percentageOfIncome: percentage,
                isExceedingBudget: isExceeding
            )
        }.sorted(by: { $0.totalSpent > $1.totalSpent })
    }

    public func generateRecommendations() throws -> [FinancialRecommendation] {
        var recommendations: [FinancialRecommendation] = []

        let netIncome = try calculateNetFixedIncome()
        let categoryReports = try analyzeCategories()

        for report in categoryReports where report.isExceedingBudget {
            let percentageFormatted = NSDecimalNumber(decimal: report.percentageOfIncome * 100).intValue
            recommendations.append(
                FinancialRecommendation(
                    title: "Atenção com \(report.categoryName)",
                    description: "Seus gastos com \(report.categoryName) comprometem \(percentageFormatted)% da sua renda fixa. Considere reduzir este item no próximo ciclo.",
                    priority: .high
                )
            )
        }

        let unexpectedDescriptor = FetchDescriptor<UnexpectedIncomeEntity>()
        let unexpectedIncomes = try modelContext.fetch(unexpectedDescriptor)
        let totalUnexpected = unexpectedIncomes.reduce(Decimal.zero) { $0 + $1.amount }

        if totalUnexpected > 0 {
            recommendations.append(
                FinancialRecommendation(
                    title: "Alocação de Renda Extra",
                    description: "Você possui R$ \(totalUnexpected) provenientes de renda inesperada. Recomenda-se alocar parte em reserva de emergência e parte em investimentos de curto/médio prazo.",
                    priority: .medium
                )
            )
        }

        if netIncome > 0 {
            let suggestedInvestment = netIncome * Decimal(0.20)
            recommendations.append(
                FinancialRecommendation(
                    title: "Oportunidade de Investimento",
                    description: "Sua renda fixa possui um saldo remanescente positivo. Sugerimos direcionar R$ \(suggestedInvestment) (20%) para investimentos conservadores/estratégicos.",
                    priority: .low
                )
            )
        }

        return recommendations
    }
}

// MARK: - Security & Privacy Layer
public final class BiometricAuthManager {
    public static let shared = BiometricAuthManager()
    private init() {}

    public enum BiometricError: Error, Equatable {
        case notAvailable
        case authFailed
        case userCanceled
        case unknown
    }

    public func authenticate(reason: String = "Acesso seguro aos seus dados no AegisFinance") async -> Result<Bool, BiometricError> {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .failure(.notAvailable)
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return success ? .success(true) : .failure(.authFailed)
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel:
                return .failure(.userCanceled)
            default:
                return .failure(.authFailed)
            }
        } catch {
            return .failure(.unknown)
        }
    }
}

public struct PrivacyBlurModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isObscured: Bool = false

    public func body(content: Content) -> some View {
        content
            .blur(radius: isObscured ? 25 : 0)
            .overlay {
                if isObscured {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                    }
                }
            }
            .onChange(of: scenePhase) { newPhase in
                withAnimation(.linear(duration: 0.1)) {
                    isObscured = (newPhase != .active)
                }
            }
    }
}

public extension View {
    func applyPrivacyShield() -> some View {
        self.modifier(PrivacyBlurModifier())
    }
}

// MARK: - Presentation: Dashboard View & ViewModel
@Observable
@MainActor
public final class DashboardViewModel {
    public var netFixedIncome: Decimal = .zero
    public var categoryReports: [CategoryExpenseReport] = []
    public var recommendations: [FinancialRecommendation] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private let engine: FinanceEngineActor

    public init(modelContext: ModelContext) {
        self.engine = FinanceEngineActor(modelContext: modelContext)
    }

    public func fetchDashboardData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let fetchedNetIncome = engine.calculateNetFixedIncome()
            async let fetchedCategories = engine.analyzeCategories()
            async let fetchedRecommendations = engine.generateRecommendations()

            self.netFixedIncome = try await fetchedNetIncome
            self.categoryReports = try await fetchedCategories
            self.recommendations = try await fetchedRecommendations
        } catch {
            self.errorMessage = "Falha ao processar dados financeiros: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DashboardViewModel?
    @State private var isSheetUnexpectedIncomePresented = false
    @State private var isSheetAddExpensePresented = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    NetIncomeHeroCard(netIncome: viewModel?.netFixedIncome ?? .zero)

                    HStack(spacing: 12) {
                        Button(action: { isSheetAddExpensePresented = true }) {
                            HStack {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                Text("Novo Gasto")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(white: 0.15))
                            .cornerRadius(12)
                        }

                        Button(action: { isSheetUnexpectedIncomePresented = true }) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.yellow)
                                Text("Renda Extra")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(white: 0.15))
                            .cornerRadius(12)
                        }
                    }

                    if let recs = viewModel?.recommendations, !recs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Análise e Recomendações")
                                .font(.title3.bold())

                            ForEach(recs, id: \.(title)) { rec in
                                RecommendationCard(recommendation: rec)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Gastos por Categoria")
                            .font(.title3.bold())

                        if let reports = viewModel?.categoryReports, reports.isEmpty {
                            Text("Nenhum gasto registrado até o momento.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else if let reports = viewModel?.categoryReports {
                            ForEach(reports, id: \.(categoryName)) { report in
                                CategoryRowView(report: report)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AegisFinance")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task { await viewModel?.fetchDashboardData() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = DashboardViewModel(modelContext: modelContext)
                }
                await viewModel?.fetchDashboardData()
            }
            .sheet(isPresented: $isSheetUnexpectedIncomePresented) {
                UnexpectedIncomeView()
                    .onDisappear { Task { await viewModel?.fetchDashboardData() } }
            }
            .sheet(isPresented: $isSheetAddExpensePresented) {
                AddExpenseView()
                    .onDisappear { Task { await viewModel?.fetchDashboardData() } }
            }
            .applyPrivacyShield()
        }
    }
}

private struct NetIncomeHeroCard: View {
    let netIncome: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SALDO DA RENDA FIXA (LÍQUIDO)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text(netIncome, format: .currency(code: "BRL"))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(netIncome >= 0 ? .green : .red)

            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Descontos aplicados automaticamente")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

private struct RecommendationCard: View {
    let recommendation: FinancialRecommendation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconForPriority(recommendation.priority))
                .foregroundColor(colorForPriority(recommendation.priority))
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.subheadline.weight(.semibold))
                Text(recommendation.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorForPriority(recommendation.priority).opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorForPriority(recommendation.priority).opacity(0.3), lineWidth: 1)
        )
    }

    private func iconForPriority(_ priority: FinancialRecommendation.Priority) -> String {
        switch priority {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "arrow.up.right.circle.fill"
        case .low: return "lightbulb.fill"
        }
    }

    private func colorForPriority(_ priority: FinancialRecommendation.Priority) -> Color {
        switch priority {
        case .high: return .orange
        case .medium: return .blue
        case .low: return .green
        }
    }
}

private struct CategoryRowView: View {
    let report: CategoryExpenseReport

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.categoryName)
                    .font(.body.weight(.medium))
                Text("\(NSDecimalNumber(decimal: report.percentageOfIncome * 100).intValue)% do orçamento")
                    .font(.caption)
                    .foregroundColor(report.isExceedingBudget ? .red : .secondary)
            }
            Spacer()
            Text(report.totalSpent, format: .currency(code: "BRL"))
                .font(.body.weight(.semibold))
                .foregroundColor(report.isExceedingBudget ? .red : .primary)
        }
        .padding()
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Presentation: Add Expense View & ViewModel
@Observable
@MainActor
public final class AddExpenseViewModel {
    public var title: String = ""
    public var amountText: String = ""
    public var selectedCategory: CategoryEntity?
    public var selectedFixedIncome: FixedIncomeEntity?
    public var expenseDate: Date = Date()

    public var isSaving: Bool = false
    public var alertMessage: String?
    public var showAlert: Bool = false
    public var shouldDismiss: Bool = false

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func saveExpense() {
        let sanitizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            presentAlert("O título do gasto não pode estar em branco.")
            return
        }

        let sanitizedAmount = amountText.replacingOccurrences(of: ",", with: ".")
        guard let decimalAmount = Decimal(string: sanitizedAmount), decimalAmount > 0 else {
            presentAlert("Insira um valor monetário válido e maior que zero.")
            return
        }

        guard let fixedIncome = selectedFixedIncome else {
            presentAlert("Selecione a fonte de Renda Fixa de onde este gasto será abatido.")
            return
        }

        isSaving = true

        let newExpense = ExpenseEntity(
            title: sanitizedTitle,
            amount: decimalAmount,
            date: expenseDate,
            category: selectedCategory,
            deductedFromIncome: fixedIncome
        )

        modelContext.insert(newExpense)
        fixedIncome.linkedExpenses.append(newExpense)

        do {
            try modelContext.save()
            isSaving = false
            shouldDismiss = true
        } catch {
            isSaving = false
            presentAlert("Erro ao salvar débito: \(error.localizedDescription)")
        }
    }

    private func presentAlert(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
}

public struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FixedIncomeEntity.sourceName) private var availableIncomes: [FixedIncomeEntity]
    @Query(sort: \CategoryEntity.name) private var availableCategories: [CategoryEntity]

    @State private var viewModel: AddExpenseViewModel?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Detalhamento do Débito")) {
                    TextField("Ex: Supermercado, Aluguel", text: Binding(
                        get: { viewModel?.title ?? "" },
                        set: { viewModel?.title = $0 }
                    ))

                    TextField("Valor (R$)", text: Binding(
                        get: { viewModel?.amountText ?? "" },
                        set: { viewModel?.amountText = $0 }
                    ))
                    .keyboardType(.decimalPad)

                    DatePicker("Data do Débito", selection: Binding(
                        get: { viewModel?.expenseDate ?? Date() },
                        set: { viewModel?.expenseDate = $0 }
                    ), displayedComponents: .date)
                }

                Section(
                    header: Text("Origem do Abatimento (Obrigatório)"),
                    footer: Text("O valor digitado será abatido diretamente do saldo desta Renda Fixa.")
                ) {
                    Picker("Renda Fixa", selection: Binding(
                        get: { viewModel?.selectedFixedIncome },
                        set: { viewModel?.selectedFixedIncome = $0 }
                    )) {
                        Text("Selecione a fonte").tag(Optional<FixedIncomeEntity>.none)
                        ForEach(availableIncomes) { income in
                            Text("\(income.sourceName) (\(income.grossAmount, format: .currency(code: \"BRL\")))")
                                .tag(Optional(income))
                        }
                    }
                }

                Section(header: Text("Classificação")) {
                    Picker("Categoria", selection: Binding(
                        get: { viewModel?.selectedCategory },
                        set: { viewModel?.selectedCategory = $0 }
                    )) {
                        Text("Sem Categoria").tag(Optional<CategoryEntity>.none)
                        ForEach(availableCategories) { category in
                            HStack {
                                Image(systemName: category.iconName)
                                Text(category.name)
                            }
                            .tag(Optional(category))
                        }
                    }
                }
            }
            .navigationTitle("Novo Gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lançar Débito") {
                        viewModel?.saveExpense()
                    }
                    .bold()
                    .disabled(viewModel?.isSaving ?? false)
                }
            }
            .onAppear {
                if viewModel == nil {
                    let vm = AddExpenseViewModel(modelContext: modelContext)
                    vm.selectedFixedIncome = availableIncomes.first
                    vm.selectedCategory = availableCategories.first
                    viewModel = vm
                }
            }
            .onChange(of: viewModel?.shouldDismiss ?? false) { _, shouldDismiss in
                if shouldDismiss { dismiss() }
            }
            .alert("Erro de Validação", isPresented: Binding(
                get: { viewModel?.showAlert ?? false },
                set: { viewModel?.showAlert = $0 }
            )) {
                Button("Corrigir", role: .cancel) { }
            } message: {
                Text(viewModel?.alertMessage ?? "")
            }
        }
    }
}

// MARK: - Presentation: Unexpected Income View & ViewModel
public enum AllocationStrategy: String, CaseIterable, Identifiable {
    case emergencyFund = "Reserva de Emergência (Liquidez Diária)"
    case longTermInvestment = "Investimento de Longo Prazo (IPCA+ / CDB)"
    case fixedIncomeBuffer = "Aportar no Saldo da Renda Fixa"

    public var id: String { self.rawValue }
}

@Observable
@MainActor
public final class UnexpectedIncomeViewModel {
    public var sourceDescription: String = ""
    public var amountText: String = ""
    public var selectedStrategy: AllocationStrategy = .emergencyFund

    public var isSaving: Bool = false
    public var alertMessage: String?
    public var showAlert: Bool = false
    public var shouldDismiss: Bool = false

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func saveUnexpectedIncome() {
        guard !sourceDescription.trimmingCharacters(in: .whitespaces).isEmpty else {
            presentAlert("A origem da receita não pode ficar em branco.")
            return
        }

        let sanitizedText = amountText.replacingOccurrences(of: ",", with: ".")
        guard let decimalAmount = Decimal(string: sanitizedText), decimalAmount > 0 else {
            presentAlert("Por favor, insira um valor monetário válido maior que zero.")
            return
        }

        isSaving = true

        let entry = UnexpectedIncomeEntity(
            sourceDescription: sourceDescription.trimmingCharacters(in: .whitespaces),
            amount: decimalAmount,
            dateReceived: Date()
        )

        modelContext.insert(entry)

        do {
            try modelContext.save()
            isSaving = false
            shouldDismiss = true
        } catch {
            isSaving = false
            presentAlert("Erro ao salvar lançamento: \(error.localizedDescription)")
        }
    }

    private func presentAlert(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
}

public struct UnexpectedIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: UnexpectedIncomeViewModel?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Origem do Valor")) {
                    TextField("Ex: Bônus de Trabalho, Restituição", text: Binding(
                        get: { viewModel?.sourceDescription ?? "" },
                        set: { viewModel?.sourceDescription = $0 }
                    ))
                    .autocorrectionDisabled()
                }

                Section(header: Text("Valor Recebido (R$)")) {
                    TextField("0,00", text: Binding(
                        get: { viewModel?.amountText ?? "" },
                        set: { viewModel?.amountText = $0 }
                    ))
                    .keyboardType(.decimalPad)
                }

                Section(
                    header: Text("Recomendação de Destinação"),
                    footer: Text("O algoritmo do AegisFinance prioriza a criação de Reserva de Emergência para rendas inesperadas.")
                ) {
                    Picker("Estratégia", selection: Binding(
                        get: { viewModel?.selectedStrategy ?? .emergencyFund },
                        set: { viewModel?.selectedStrategy = $0 }
                    )) {
                        ForEach(AllocationStrategy.allCases) { strategy in
                            Text(strategy.rawValue).tag(strategy)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Dinheiro Inesperado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmar") {
                        viewModel?.saveUnexpectedIncome()
                    }
                    .disabled(viewModel?.isSaving ?? false)
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = UnexpectedIncomeViewModel(modelContext: modelContext)
                }
            }
            .onChange(of: viewModel?.shouldDismiss ?? false) { _, shouldDismiss in
                if shouldDismiss { dismiss() }
            }
            .alert("Atenção", isPresented: Binding(
                get: { viewModel?.showAlert ?? false },
                set: { viewModel?.showAlert = $0 }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel?.alertMessage ?? "")
            }
        }
    }
}
