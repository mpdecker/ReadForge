//
//  SectionPickerView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

struct SectionPickerView: View {
    let sections: [SectionRecord]
    @Binding var selectedIndex: Int
    let onSelectionChange: (Int) -> Void
    
    var body: some View {
        Picker("Section", selection: $selectedIndex) {
            ForEach(sections.indices, id: \.self) { index in
                Text(sections[index].title).tag(index)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .onChange(of: selectedIndex) { oldValue, newValue in
            if oldValue != newValue {
                onSelectionChange(newValue)
            }
        }
    }
}
