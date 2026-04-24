import SwiftUI

/// Owner-only sheet to edit a group's name + description. Image editing is
/// intentionally deferred until the backend supports image uploads.
struct EditGroupSheet: View {

    @Bindable var viewModel: GroupDetailViewModel
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedName != (viewModel.group?.name ?? "")
            || description.trimmingCharacters(in: .whitespacesAndNewlines)
                != (viewModel.group?.description ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    nameField
                    descriptionField
                    Spacer()
                    saveButton
                }
                .padding()
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .tint(Color.xomifyGreen)
        }
        .presentationDetents([.medium])
        .onAppear {
            name = viewModel.group?.name ?? ""
            description = viewModel.group?.description ?? ""
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.caption)
                .foregroundStyle(.gray)
            TextField("Group name", text: $name)
                .textInputAutocapitalization(.words)
                .padding()
                .background(Color.white.opacity(0.05))
                .clipShape(.rect(cornerRadius: 10))
                .foregroundStyle(.white)
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.caption)
                .foregroundStyle(.gray)
            TextField("What's this group about?", text: $description, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color.white.opacity(0.05))
                .clipShape(.rect(cornerRadius: 10))
                .foregroundStyle(.white)
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                if await viewModel.saveEdit(name: name, description: description) {
                    onDismiss()
                }
            }
        } label: {
            HStack {
                if viewModel.isSavingEdit {
                    ProgressView().tint(.white)
                } else {
                    Text("Save")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(LinearGradient.xomifyGradient)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 22))
            .opacity((trimmedName.isEmpty || !hasChanges) ? 0.5 : 1)
        }
        .disabled(viewModel.isSavingEdit || trimmedName.isEmpty || !hasChanges)
        .accessibilityLabel("Save group changes")
    }
}
