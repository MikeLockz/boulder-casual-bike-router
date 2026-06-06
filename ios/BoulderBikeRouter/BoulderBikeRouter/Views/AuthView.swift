import SwiftUI

struct AuthView: View {
    var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSignUpMode = false
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    
    private var isFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty,
              trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            return false
        }
        guard password.count >= 8 else {
            return false
        }
        if isSignUpMode {
            return password == passwordConfirm
        }
        return true
    }
    
    var body: some View {
        ZStack {
            Color.forestDeep
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header / Close button
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.onSurfaceVariant.opacity(0.6))
                        }
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }
                    
                    // Logo & Header
                    VStack(spacing: 12) {
                        Image(systemName: "bicycle.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.mintGlow)
                            .shadow(color: .mintGlow.opacity(0.3), radius: 8)
                        
                        Text("Biking Boulder")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.onSurface)
                        
                        Text(isSignUpMode ? "Create an account to sync your routes" : "Sign in to access your saved trips")
                            .font(.system(size: 14))
                            .foregroundColor(.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 20)
                    
                    // Mode Selector Segmented Control
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSignUpMode = false
                                errorMessage = nil
                                successMessage = nil
                            }
                        }) {
                            Text("Sign In")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isSignUpMode ? .onSurfaceVariant : .forestDeep)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSignUpMode ? Color.clear : Color.primaryMint)
                        }
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSignUpMode = true
                                errorMessage = nil
                                successMessage = nil
                            }
                        }) {
                            Text("Create Account")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isSignUpMode ? .forestDeep : .onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSignUpMode ? Color.primaryMint : Color.clear)
                        }
                    }
                    .background(Color.surfaceElevated)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.onSurfaceVariant.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    
                    // Input Fields Box
                    VStack(spacing: 16) {
                        // Email
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL ADDRESS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.onSurfaceVariant)
                                .tracking(1)
                            
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.onSurfaceVariant)
                                    .frame(width: 20)
                                
                                TextField("email@example.com", text: $email)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .foregroundColor(.onSurface)
                            }
                            .padding(14)
                            .background(Color.surfaceDim)
                            .cornerRadius(8)
                        }
                        
                        // Password
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PASSWORD (MIN 8 CHARACTERS)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.onSurfaceVariant)
                                .tracking(1)
                            
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.onSurfaceVariant)
                                    .frame(width: 20)
                                
                                SecureField("••••••••", text: $password)
                                    .foregroundColor(.onSurface)
                            }
                            .padding(14)
                            .background(Color.surfaceDim)
                            .cornerRadius(8)
                        }
                        
                        // Confirm Password (Sign Up Only)
                        if isSignUpMode {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("CONFIRM PASSWORD")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.onSurfaceVariant)
                                    .tracking(1)
                                
                                HStack {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(.onSurfaceVariant)
                                        .frame(width: 20)
                                    
                                    SecureField("••••••••", text: $passwordConfirm)
                                        .foregroundColor(.onSurface)
                                }
                                .padding(14)
                                .background(Color.surfaceDim)
                                .cornerRadius(8)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Feedback messages (Error/Success)
                    if let errorMessage = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.errorRose)
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.errorRose)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.errorContainer.opacity(0.2))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.errorRose.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                    }
                    
                    if let successMessage = successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.successTeal)
                            Text(successMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.successTeal)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.successTeal.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.successTeal.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                    }
                    
                    // Submit Button
                    Button(action: handleSubmit) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.forestDeep)
                                    .padding(.trailing, 8)
                            }
                            
                            Text(isLoading ? "Processing..." : (isSignUpMode ? "Create Account" : "Sign In"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.forestDeep)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isFormValid && !isLoading ? Color.mintGlow : Color.onSurfaceVariant.opacity(0.3))
                        .cornerRadius(8)
                        .shadow(color: isFormValid && !isLoading ? Color.mintGlow.opacity(0.2) : Color.clear, radius: 8)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    private func handleSubmit() {
        guard isFormValid else { return }
        
        errorMessage = nil
        successMessage = nil
        isLoading = true
        
        Task {
            do {
                if isSignUpMode {
                    try await viewModel.signUp(email: email, password: password)
                    await MainActor.run {
                        successMessage = "Account created and logged in!"
                        isLoading = false
                        // Automatically close the sheet after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            dismiss()
                        }
                    }
                } else {
                    try await viewModel.signIn(email: email, password: password)
                    await MainActor.run {
                        successMessage = "Logged in successfully!"
                        isLoading = false
                        // Close sheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
